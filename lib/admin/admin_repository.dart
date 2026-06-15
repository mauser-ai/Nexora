import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../data/team_repository.dart';
import '../models/domain_models.dart';
import '../models/subscription_models.dart';

// ────────────────────────────────────────────────
// ID dell'unico utente con accesso admin
// ────────────────────────────────────────────────
const kAdminUid = 'XTsWw4FJeic7AzmCIg1YoNTT9I73';

// ────────────────────────────────────────────────
// AdminTeam – snapshot di un team con tutti i dettagli
// ────────────────────────────────────────────────

class AdminTeam {
  const AdminTeam({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.members,
    required this.memberCount,
    required this.createdAt,
    this.billingProfile,
    this.subscription,
  });

  final String id;
  final String name;
  final String ownerId;
  final List<TeamMember> members;
  final int memberCount;
  final DateTime createdAt;
  final BillingProfile? billingProfile;
  final TeamSubscription? subscription;

  TeamMember? get owner => members.where((m) => m.userId == ownerId).firstOrNull;

  int get activeLicenses => members.where((m) => m.status == 'active').length;

  int get availableLicenses {
    final plan = subscription?.plan;
    if (plan == null) return 0;
    if (plan.isUnlimited) return 999;
    return (plan.maxUsers - activeLicenses).clamp(0, plan.maxUsers);
  }

  bool get canAddMember {
    final plan = subscription?.plan;
    if (plan == null) return false;
    if (plan.isUnlimited) return true;
    return activeLicenses < plan.maxUsers;
  }
}

// ────────────────────────────────────────────────
// AdminRepository
// Lettura/scrittura di tutti i team e utenti.
// Solo kAdminUid può usare queste API.
// ────────────────────────────────────────────────

class AdminRepository {
  AdminRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ── Watch all teams ──

  Stream<List<AdminTeam>> watchAllTeams() {
    return _db.collection('teams').snapshots().asyncMap((snap) async {
      final teams = <AdminTeam>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final membersSnap = await _db
            .collection('teams')
            .doc(doc.id)
            .collection('members')
            .get();
        final members = membersSnap.docs
            .map((d) => TeamMember.fromMap(d.id, d.data()))
            .toList();

        final billingData = data['billingProfile'] as Map<String, dynamic>?;
        final billing = billingData != null ? BillingProfile.fromMap(billingData) : null;
        final subData = data['subscription'] as Map<String, dynamic>?;
        final subscription = TeamSubscription.fromMap(subData);

        teams.add(AdminTeam(
          id: doc.id,
          name: data['name'] as String? ?? '—',
          ownerId: data['ownerId'] as String? ?? '',
          members: members,
          memberCount: members.length,
          createdAt: data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          billingProfile: billing,
          subscription: subscription,
        ));
      }
      teams.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return teams;
    });
  }

  // ── Watch all users (che hanno un profilo in users/) ──

  Stream<List<Map<String, dynamic>>> watchAllUsers() {
    return _db.collection('users').snapshots().map((snap) => snap.docs
        .map((d) => {'uid': d.id, ...d.data()})
        .toList()
      ..sort((a, b) => (a['displayName'] as String? ?? '').compareTo(b['displayName'] as String? ?? '')));
  }

  // ── Create Firebase Auth user via REST API ──
  // Non usa secondary Firebase app (non funziona su web).
  // Usa direttamente l'endpoint identitytoolkit per creare utenti
  // senza interferire con la sessione auth corrente.

  Future<String?> _createAuthUser({
    required String email,
    required String password,
  }) async {
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
      return body['localId'] as String?; // UID del nuovo utente
    }

    final errorCode = (body['error'] as Map?)?['message'] as String? ?? '';

    if (errorCode.contains('EMAIL_EXISTS')) {
      // Utente già esistente — cerca il suo UID su Firestore
      final q = await _db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.id;
      return null; // Email esiste in Auth ma non ha profilo Firestore
    }

    throw Exception('Errore creazione account: $errorCode');
  }

  // ── Create a new team ──

  Future<String> createTeam({
    required String name,
    required String ownerEmail,
    required String ownerDisplayName,
    required String ownerRole,
    required String ownerPassword,
  }) async {
    // 1. Crea utente Firebase Auth via REST (no secondary app — funziona su web)
    final newUid = await _createAuthUser(email: ownerEmail, password: ownerPassword);
    if (newUid == null) throw Exception('Impossibile creare account Firebase per $ownerEmail');

    // 2. Create team in Firestore
    final teamId = 'team-${newUid.substring(0, 8)}';
    final now = DateTime.now();
    final batch = _db.batch();

    batch.set(_db.collection('teams').doc(teamId), {
      'name': name,
      'ownerId': newUid,
      'createdAt': Timestamp.fromDate(now),
    });
    batch.set(_db.collection('teams').doc(teamId).collection('members').doc(newUid), {
      'userId': newUid,
      'email': ownerEmail,
      'displayName': ownerDisplayName,
      'role': ownerRole,
      'status': 'active',
      'joinedAt': Timestamp.fromDate(now),
    });
    batch.set(_db.collection('users').doc(newUid), {
      'teamId': teamId,
      'displayName': ownerDisplayName,
      'role': ownerRole,
      'email': ownerEmail,
    }, SetOptions(merge: true));

    await batch.commit();
    return teamId;
  }

  // ── Add member to existing team ──

  Future<void> addMemberToTeam({
    required String teamId,
    required String email,
    required String displayName,
    required String role,
    required String password,
  }) async {
    // Crea utente via REST (no secondary app)
    final newUid = await _createAuthUser(email: email, password: password);
    if (newUid == null) throw Exception('Impossibile creare/trovare account per $email');

    final batch = _db.batch();
    batch.set(_db.collection('teams').doc(teamId).collection('members').doc(newUid), {
      'userId': newUid, 'email': email, 'displayName': displayName, 'role': role,
      'status': 'active', 'joinedAt': Timestamp.fromDate(DateTime.now()),
    });
    batch.set(_db.collection('users').doc(newUid), {
      'teamId': teamId, 'displayName': displayName, 'role': role, 'email': email,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  // ── Remove member from team ──

  Future<void> removeMember({required String teamId, required String userId}) async {
    final batch = _db.batch();
    batch.delete(_db.collection('teams').doc(teamId).collection('members').doc(userId));
    batch.update(_db.collection('users').doc(userId), {'teamId': FieldValue.delete()});
    await batch.commit();
  }

  // ── Delete team ──

  Future<void> deleteTeam(String teamId) async {
    // Remove teamId from all members
    final members = await _db.collection('teams').doc(teamId).collection('members').get();
    final batch = _db.batch();
    for (final m in members.docs) {
      batch.delete(m.reference);
      batch.update(_db.collection('users').doc(m.id), {'teamId': FieldValue.delete()});
    }
    batch.delete(_db.collection('teams').doc(teamId));
    await batch.commit();
  }

  // ── Update team name ──

  Future<void> updateTeamName(String teamId, String name) =>
      _db.collection('teams').doc(teamId).update({'name': name});

  // ── Update team billing profile ──

  Future<void> updateTeamBilling(String teamId, BillingProfile profile) =>
      _db.collection('teams').doc(teamId).update({'billingProfile': profile.toMap()});

  Future<void> updateTeamSubscription(String teamId, TeamSubscription sub) =>
      _db.collection('teams').doc(teamId).set(
        {'subscription': sub.toMap()}, SetOptions(merge: true));

  Future<TeamSubscription> getTeamSubscription(String teamId) async {
    final doc = await _db.collection('teams').doc(teamId).get();
    return TeamSubscription.fromMap(
      doc.data()?['subscription'] as Map<String, dynamic>?,
    );
  }

  // ── Get team billing (for team members in CRM) ──

  Future<BillingProfile?> getTeamBilling(String teamId) async {
    final doc = await _db.collection('teams').doc(teamId).get();
    final data = doc.data()?['billingProfile'] as Map<String, dynamic>?;
    return data != null ? BillingProfile.fromMap(data) : null;
  }

  Stream<BillingProfile> watchTeamBilling(String teamId) {
    return _db.collection('teams').doc(teamId).snapshots().map((doc) {
      final data = doc.data()?['billingProfile'] as Map<String, dynamic>?;
      return BillingProfile.fromMap(data);
    });
  }

  // ── User activity summary ──

  Future<Map<String, dynamic>> getUserActivity(String userId) async {
    final timeTracks = await _db.collection('users').doc(userId).collection('timeTracks').get();
    final tasks = await _db.collection('users').doc(userId).collection('tasks').get();
    final invoices = await _db.collection('users').doc(userId).collection('invoices').get();

    double totalHours = 0;
    for (final doc in timeTracks.docs) {
      final data = doc.data();
      final start = data['startAt'];
      final end = data['endAt'];
      if (start is Timestamp && end is Timestamp) {
        totalHours += end.toDate().difference(start.toDate()).inMinutes / 60;
      }
    }

    return {
      'timeTracksCount': timeTracks.size,
      'totalHours': totalHours,
      'tasksCount': tasks.size,
      'invoicesCount': invoices.size,
      'lastActivity': timeTracks.docs.isNotEmpty
          ? (timeTracks.docs.last.data()['startAt'] as Timestamp?)?.toDate()
          : null,
    };
  }
}
