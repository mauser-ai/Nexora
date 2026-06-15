import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'api_client.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../models/subscription_models.dart';

// ────────────────────────────────────────────────
// Teamleader-inspired team structure:
//   teams/{teamId}/
//     - name, ownerId, createdAt
//     members/{userId}/
//       - userId, email, displayName, role (function), status, joinedAt
//
//   users/{userId}/
//     - teamId (link to team)
//     - displayName, role
//     - billingProfile (existing)
// ────────────────────────────────────────────────

class TeamMember {
  const TeamMember({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
    this.joinedAt,
  });

  final String userId;
  final String email;
  final String displayName;
  final String role; // Teamleader: user.function
  final String status; // active | deactivated
  final DateTime? joinedAt;

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  }

  factory TeamMember.fromMap(String id, Map<String, dynamic> m) => TeamMember(
    userId: id,
    email: m['email'] as String? ?? '',
    displayName: m['displayName'] as String? ?? '',
    role: m['role'] as String? ?? '',
    status: m['status'] as String? ?? 'active',
    joinedAt: m['joinedAt'] is Timestamp
        ? (m['joinedAt'] as Timestamp).toDate()
        : null,
  );

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'email': email,
    'displayName': displayName,
    'role': role,
    'status': status,
    'joinedAt': joinedAt != null
        ? Timestamp.fromDate(joinedAt!)
        : FieldValue.serverTimestamp(),
  };
}

class TeamInfo {
  const TeamInfo({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.members,
    this.createdAt,
    this.subscription,
    this.brandLogoUrl,
    this.brandColor,
  });

  final String id;
  final String name;
  final String ownerId;
  final List<TeamMember> members;
  final DateTime? createdAt;
  final TeamSubscription? subscription;
  final String? brandLogoUrl; // URL logo team (Firebase Storage)
  final String? brandColor;   // Hex colore brand, es. '#10B981'

  List<TeamMember> get activeMembers =>
      members.where((m) => m.status == 'active').toList();

  TeamMember? memberById(String userId) =>
      members.where((m) => m.userId == userId).firstOrNull;

  List<String> get memberUserIds => members.map((m) => m.userId).toList();

  bool get hasActiveSubscription =>
      subscription != null && subscription!.isActive;
}

// ────────────────────────────────────────────────
// TeamRepository
// ────────────────────────────────────────────────

class TeamRepository {
  TeamRepository({FirebaseFirestore? firestore, ApiClient? api})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = api ?? ApiClient.instance;

  final FirebaseFirestore _db;
  final ApiClient _api;
  static const int _maxMemberTaskDocs = 1200;
  static const int _maxMemberTrackDocs = 1500;

  /// Probe sull'API team MySQL (null = non verificato).
  static bool? _apiMode;

  Future<bool> _useApi() async {
    if (_apiMode != null) return _apiMode!;
    try {
      final raw = await _api.get('/app/team.php');
      _apiMode = raw is Map && raw.containsKey('team');
    } catch (_) {
      _apiMode = false;
    }
    return _apiMode!;
  }

  TeamInfo? _teamFromApi(dynamic raw) {
    final data = raw is Map ? raw['team'] : null;
    if (data is! Map) return null;
    final members = ((data['members'] as List?) ?? [])
        .whereType<Map>()
        .map(
          (m) => TeamMember(
            userId: (m['userId'] ?? '').toString(),
            email: (m['email'] ?? '').toString(),
            displayName: (m['displayName'] ?? '').toString(),
            role: (m['role'] ?? '').toString(),
            status: (m['status'] ?? 'active').toString(),
            joinedAt: DateTime.tryParse((m['joinedAt'] ?? '').toString()),
          ),
        )
        .toList();
    return TeamInfo(
      id: (data['id'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      ownerId: (data['ownerId'] ?? '').toString(),
      members: members,
      createdAt: DateTime.tryParse((data['createdAt'] ?? '').toString()),
      brandLogoUrl: ((data['brandLogoUrl'] ?? '') as String).isEmpty
          ? null
          : (data['brandLogoUrl'] as String),
      brandColor: ((data['brandColor'] ?? '') as String).isEmpty
          ? null
          : (data['brandColor'] as String),
    );
  }

  /// Branding (logo) di un team specifico — usato per i PDF.
  Future<String?> fetchTeamBrandLogo(String teamId) async {
    if (await _useApi()) {
      try {
        final raw = await _api.get('/app/team.php', query: {'id': teamId});
        final team = _teamFromApi(raw);
        return team?.brandLogoUrl;
      } catch (_) {
        return null;
      }
    }
    try {
      final doc = await _db.collection('teams').doc(teamId).get();
      return (doc.data()?['brandLogoUrl'] as String?)?.trim();
    } catch (_) {
      return null;
    }
  }

  /// Aggiorna il branding del proprio team (nome, logo, colore).
  Future<void> updateTeamBranding(
    String teamId, {
    String? name,
    String? brandLogoUrl,
    String? brandColor,
    bool removeLogo = false,
  }) async {
    if (await _useApi()) {
      await _api.put('/app/team.php', {
        if (name != null) 'name': name,
        if (brandLogoUrl != null || removeLogo)
          'brandLogoUrl': removeLogo ? '' : brandLogoUrl,
        if (brandColor != null) 'brandColor': brandColor,
      });
      return;
    }
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (removeLogo) {
      data['brandLogoUrl'] = FieldValue.delete();
    } else if (brandLogoUrl != null) {
      data['brandLogoUrl'] = brandLogoUrl;
    }
    if (brandColor != null) data['brandColor'] = brandColor;
    if (data.isEmpty) return;
    await _db
        .collection('teams')
        .doc(teamId)
        .set(data, SetOptions(merge: true));
  }

  // ── Watch team for current user ──

  Stream<TeamInfo?> watchUserTeam(String userId) {
    final ctrl = StreamController<TeamInfo?>.broadcast();

    // Modalità API MySQL: fetch singolo (il team cambia raramente).
    unawaited(() async {
      if (await _useApi()) {
        try {
          final raw = await _api.get('/app/team.php');
          if (!ctrl.isClosed) ctrl.add(_teamFromApi(raw));
        } catch (_) {
          if (!ctrl.isClosed) ctrl.add(null);
        }
      }
    }());

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? teamSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? membersSub;
    String? currentTeamId;
    Map<String, dynamic>? currentTeamData;
    List<TeamMember> currentMembers = const [];

    void emitTeamIfReady() {
      if (ctrl.isClosed) return;
      if (currentTeamId == null || currentTeamData == null) return;
      final subData = currentTeamData!['subscription'] as Map<String, dynamic>?;
      ctrl.add(
        TeamInfo(
          id: currentTeamId!,
          name: currentTeamData!['name'] as String? ?? '',
          ownerId: currentTeamData!['ownerId'] as String? ?? '',
          members: currentMembers,
          createdAt: currentTeamData!['createdAt'] is Timestamp
              ? (currentTeamData!['createdAt'] as Timestamp).toDate()
              : null,
          subscription: TeamSubscription.fromMap(subData),
          brandLogoUrl: currentTeamData!['brandLogoUrl'] as String?,
          brandColor:   currentTeamData!['brandColor']   as String?,
        ),
      );
    }

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? userSub;
    unawaited(() async {
      if (await _useApi()) return; // gestito sopra via API
      userSub = _db.collection('users').doc(userId).snapshots().listen((
      userDoc,
    ) async {
      final teamId = userDoc.data()?['teamId'] as String?;
      if (teamId == null) {
        currentTeamId = null;
        currentTeamData = null;
        currentMembers = const [];
        ctrl.add(null);
        return;
      }

      // Cancel previous team sub
      await teamSub?.cancel();
      await membersSub?.cancel();
      currentTeamId = teamId;
      currentTeamData = null;
      currentMembers = const [];

      // Watch team metadata
      teamSub = _db.collection('teams').doc(teamId).snapshots().listen((
        teamDoc,
      ) {
        final data = teamDoc.data();
        if (data == null) {
          ctrl.add(null);
          return;
        }
        currentTeamData = data;
        emitTeamIfReady();
      });

      // Also watch members collection for real-time changes
      membersSub = _db
          .collection('teams')
          .doc(teamId)
          .collection('members')
          .snapshots()
          .listen((membersSnapshot) {
            currentMembers = membersSnapshot.docs
                .map((d) => TeamMember.fromMap(d.id, d.data()))
                .toList();
            emitTeamIfReady();
          });
    });
    }());

    ctrl.onCancel = () async {
      await userSub?.cancel();
      await teamSub?.cancel();
      await membersSub?.cancel();
    };

    return ctrl.stream;
  }

  // ── Create team ──

  Future<String> createTeam({
    required String name,
    required String ownerId,
    required String ownerEmail,
    required String ownerDisplayName,
    required String ownerRole,
  }) async {
    final teamId = 'team-${ownerId.substring(0, 8)}';
    final now = DateTime.now();
    final batch = _db.batch();

    batch.set(_db.collection('teams').doc(teamId), {
      'name': name,
      'ownerId': ownerId,
      'createdAt': Timestamp.fromDate(now),
    });

    batch.set(
      _db.collection('teams').doc(teamId).collection('members').doc(ownerId),
      {
        'userId': ownerId,
        'email': ownerEmail,
        'displayName': ownerDisplayName,
        'role': ownerRole,
        'status': 'active',
        'joinedAt': Timestamp.fromDate(now),
      },
    );

    batch.set(_db.collection('users').doc(ownerId), {
      'teamId': teamId,
      'displayName': ownerDisplayName,
      'role': ownerRole,
    }, SetOptions(merge: true));

    await batch.commit();
    return teamId;
  }

  // ── Add member to team ──

  Future<void> addTeamMember({
    required String teamId,
    required TeamMember member,
  }) async {
    final batch = _db.batch();
    batch.set(
      _db
          .collection('teams')
          .doc(teamId)
          .collection('members')
          .doc(member.userId),
      member.toMap(),
    );
    batch.set(_db.collection('users').doc(member.userId), {
      'teamId': teamId,
      'displayName': member.displayName,
      'role': member.role,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  // ── Seed Gweb SRL team on first login ──
  // Crea il team "Gweb SRL" se l'utente non ha ancora un teamId,
  // poi tenta di creare il secondo utente Claudia.

  Future<void> seedGwebTeam({
    required String currentUserId,
    required String currentUserEmail,
  }) async {
    // In modalità MySQL il team personale viene creato dal server alla
    // prima GET di /app/team.php: il seed Firestore non serve.
    if (await _useApi()) return;
    return seedGwebTeam_impl(
      currentUserId: currentUserId,
      currentUserEmail: currentUserEmail,
    );
  }

  Future<void> seedGwebTeam_impl({
    required String currentUserId,
    required String currentUserEmail,
  }) async {
    // Check if user already has a team
    final userDoc = await _db.collection('users').doc(currentUserId).get();
    if (userDoc.data()?['teamId'] != null) return;

    // Determine name/role from email
    final displayName = _displayNameFromEmail(currentUserEmail);
    final role = _roleFromEmail(currentUserEmail);

    // Create team
    final teamId = await createTeam(
      name: 'Gweb SRL',
      ownerId: currentUserId,
      ownerEmail: currentUserEmail,
      ownerDisplayName: displayName,
      ownerRole: role,
    );

    // Try to create Claudia's account
    await _ensureSecondUser(teamId: teamId);
  }

  String _displayNameFromEmail(String email) {
    if (email.contains('riccardo')) return 'Riccardo Sacchetto';
    if (email.contains('claudia')) return 'Claudia Gottardello';
    final local = email.split('@')[0];
    final parts = local.split('.');
    return parts
        .map(
          (p) => p.isNotEmpty ? '${p[0].toUpperCase()}${p.substring(1)}' : '',
        )
        .join(' ');
  }

  String _roleFromEmail(String email) {
    if (email.contains('riccardo')) return 'Fullstack Developer';
    if (email.contains('claudia')) return 'UXUI Designer';
    return 'Team Member';
  }

  // Crea un utente Firebase Auth via REST API.
  // Non usa secondary app (non affidabile su web).
  // Restituisce il UID del nuovo utente o null se già esiste.
  Future<String?> _createAuthUserRest({
    required String email,
    required String password,
  }) async {
    try {
      final apiKey = Firebase.app().options.apiKey;
      final uri = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
      );
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return body['localId'] as String?;
      }
      final errorCode = (body['error'] as Map?)?['message'] as String? ?? '';
      if (errorCode.contains('EMAIL_EXISTS')) {
        // Cerca il profilo Firestore per ottenere l'UID
        final q = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        return q.docs.isNotEmpty ? q.docs.first.id : null;
      }
    } catch (_) {
      // Ignora: il team owner può invitare manualmente
    }
    return null;
  }

  Future<void> _ensureSecondUser({required String teamId}) async {
    const claudiaEmail = 'claudia.gottardello@gweb.agency';
    const claudiaPassword = 'Gweb12345';
    const claudiaName = 'Claudia Gottardello';
    const claudiaRole = 'UXUI Designer';

    try {
      // Crea o trova l'account di Claudia via REST
      final claudiaUid = await _createAuthUserRest(
        email: claudiaEmail,
        password: claudiaPassword,
      );

      if (claudiaUid == null) return; // Non riuscito — skip silenzioso

      // Controlla se è già nel team
      final existing = await _db
          .collection('teams')
          .doc(teamId)
          .collection('members')
          .doc(claudiaUid)
          .get();
      if (existing.exists) return; // Già membro

      // Aggiunge al team
      await addTeamMember(
        teamId: teamId,
        member: TeamMember(
          userId: claudiaUid,
          email: claudiaEmail,
          displayName: claudiaName,
          role: claudiaRole,
          status: 'active',
          joinedAt: DateTime.now(),
        ),
      );

      // Salva profilo Firestore
      await _db.collection('users').doc(claudiaUid).set({
        'email': claudiaEmail,
        'teamId': teamId,
        'displayName': claudiaName,
        'role': claudiaRole,
      }, SetOptions(merge: true));
    } catch (_) {
      // Qualsiasi errore ignorato — può essere invitata manualmente
    }
  }

  // ── Watch a member's time tracks (read-only for team visibility) ──

  Stream<List<Map<String, dynamic>>> watchMemberTimeTracks(String memberId) {
    return _db
        .collection('users')
        .doc(memberId)
        .collection('timeTracks')
        .orderBy('startAt', descending: true)
        .limit(_maxMemberTrackDocs)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
        );
  }

  // ── Watch a member's tasks (read-only for team visibility) ──

  Stream<List<Map<String, dynamic>>> watchMemberTasks(
    String memberId, {
    int taskLimit = _maxMemberTaskDocs,
  }) {
    return _db
        .collection('users')
        .doc(memberId)
        .collection('tasks')
        .orderBy('deadline', descending: true)
        .limit(taskLimit.clamp(20, _maxMemberTaskDocs))
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
        );
  }

  // ── Get team member display name ──

  Future<String> getMemberDisplayName(String userId) async {
    final doc = await _db.collection('users').doc(userId).get();
    return doc.data()?['displayName'] as String? ?? userId;
  }
}
