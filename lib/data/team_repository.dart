import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'api_client.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../models/custom_field_models.dart';
import '../models/roles.dart';
import '../models/subscription_models.dart';

abstract final class TeamExtraModule {
  static const nexoraAi = 'nexora_ai';
  static const teamChat = 'team_chat';
  static const integrations = 'integrations';
  static const bandi = 'bandi';
  static const customBranding = 'custom_branding';
  static const nexoraPos = 'nexora_pos';

  static const all = <String>[
    nexoraAi,
    teamChat,
    integrations,
    bandi,
    customBranding,
    nexoraPos,
  ];
}

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

  Map<String, dynamic> toApiMap() => {
    'userId': userId,
    'email': email,
    'displayName': displayName,
    'role': role,
    'status': status,
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
    this.enabledModules = const [],
    this.customFieldDefinitions = const [],
    this.teamRoles = const [],
    this.appliedPackageIds = const [],
  });

  final String id;
  final String name;
  final String ownerId;
  final List<TeamMember> members;
  final DateTime? createdAt;
  final TeamSubscription? subscription;
  final String? brandLogoUrl; // URL logo team (Firebase Storage)
  final String? brandColor; // Hex colore brand, es. '#10B981'
  final List<String> enabledModules;
  final List<TeamCustomFieldDefinition> customFieldDefinitions;
  final List<String> teamRoles;
  final List<String> appliedPackageIds;

  List<TeamMember> get activeMembers =>
      members.where((m) => m.status == 'active').toList();

  TeamMember? memberById(String userId) =>
      members.where((m) => m.userId == userId).firstOrNull;

  List<String> get memberUserIds => members.map((m) => m.userId).toList();

  bool get hasActiveSubscription =>
      subscription != null && subscription!.isActive;

  bool hasModule(String moduleId) => enabledModules.contains(moduleId);

  List<String> get availableRoles {
    final configured = GussoniRoles.normalize(teamRoles);
    if (configured.isNotEmpty) return configured;
    return GussoniRoles.all;
  }

  List<TeamCustomFieldDefinition> fieldsForModule(CustomFieldModule module) {
    return customFieldDefinitions
        .where((field) => field.module == module)
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  TeamInfo copyWith({
    String? id,
    String? name,
    String? ownerId,
    List<TeamMember>? members,
    DateTime? createdAt,
    TeamSubscription? subscription,
    String? brandLogoUrl,
    bool clearBrandLogoUrl = false,
    String? brandColor,
    bool clearBrandColor = false,
    List<String>? enabledModules,
    List<TeamCustomFieldDefinition>? customFieldDefinitions,
    List<String>? teamRoles,
    List<String>? appliedPackageIds,
  }) {
    return TeamInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      members: members ?? this.members,
      createdAt: createdAt ?? this.createdAt,
      subscription: subscription ?? this.subscription,
      brandLogoUrl: clearBrandLogoUrl
          ? null
          : (brandLogoUrl ?? this.brandLogoUrl),
      brandColor: clearBrandColor ? null : (brandColor ?? this.brandColor),
      enabledModules: enabledModules ?? this.enabledModules,
      customFieldDefinitions:
          customFieldDefinitions ?? this.customFieldDefinitions,
      teamRoles: teamRoles ?? this.teamRoles,
      appliedPackageIds: appliedPackageIds ?? this.appliedPackageIds,
    );
  }
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
      throw ApiException(
        'API team MySQL non disponibile. Installa/carica /api/app/install.php e /api/app/team.php.',
      );
    }
    if (_apiMode != true) {
      throw ApiException('Risposta API team MySQL non valida.');
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
      enabledModules: ((data['enabledModules'] as List?) ?? const [])
          .map((module) => module.toString())
          .where(TeamExtraModule.all.contains)
          .toList(),
      customFieldDefinitions:
          ((data['customFieldDefinitions'] as List?) ?? const [])
              .whereType<Map>()
              .map(
                (field) => TeamCustomFieldDefinition.fromMap(
                  Map<String, dynamic>.from(field),
                ),
              )
              .where((field) => field.id.isNotEmpty && field.label.isNotEmpty)
              .toList(),
      teamRoles: GussoniRoles.normalize(
        ((data['teamRoles'] as List?) ?? const []).map(
          (role) => role.toString(),
        ),
      ),
      appliedPackageIds: ((data['appliedPackageIds'] as List?) ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(),
    );
  }

  /// Branding (logo) di un team specifico — usato per i PDF.
  Future<String?> fetchTeamBrandLogo(String teamId) async {
    if (await _useApi()) {
      final raw = await _api.get('/app/team.php', query: {'id': teamId});
      final team = _teamFromApi(raw);
      return team?.brandLogoUrl;
    }
    return null;
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
    throw ApiException('API team MySQL non disponibile.');
  }

  Future<void> updateTeamCustomFields(
    List<TeamCustomFieldDefinition> definitions,
  ) async {
    await _useApi();
    await _api.put('/app/team.php', {
      'customFieldDefinitions': definitions
          .map((field) => field.toMap())
          .toList(),
    });
  }

  Future<void> updateTeamRoles(List<String> roles) async {
    await _useApi();
    await _api.put('/app/team.php', {
      'teamRoles': GussoniRoles.normalize(roles),
    });
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

    Timer? pollTimer;
    Future<void> refresh() async {
      try {
        final raw = await _api.get('/app/team.php');
        if (!ctrl.isClosed) ctrl.add(_teamFromApi(raw));
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    unawaited(() async {
      await _useApi();
      await refresh();
      pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (ctrl.hasListener) unawaited(refresh());
      });
    }());

    ctrl.onCancel = () async => pollTimer?.cancel();

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
    throw ApiException(
      'Creazione team arbitraria non disponibile da client. Usa l’endpoint admin MySQL.',
    );
  }

  // ── Add member to team ──

  Future<void> addTeamMember({
    required String teamId,
    required TeamMember member,
  }) async {
    await _useApi();
    await _api.post('/app/team.php', {'member': member.toApiMap()});
  }

  // ── Seed Gweb SRL team on first login ──
  // Crea il team "Gweb SRL" se l'utente non ha ancora un teamId,
  // poi tenta di creare il secondo utente Claudia.

  Future<void> seedGwebTeam({
    required String currentUserId,
    required String currentUserEmail,
  }) async {
    await _useApi();
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
