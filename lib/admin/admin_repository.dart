import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../data/api_client.dart';
import '../data/team_repository.dart';
import '../models/configuration_package_models.dart';
import '../models/domain_models.dart';
import '../models/subscription_models.dart';

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
    this.enabledModules = const [],
    this.appliedPackageIds = const [],
  });

  final String id;
  final String name;
  final String ownerId;
  final List<TeamMember> members;
  final int memberCount;
  final DateTime createdAt;
  final BillingProfile? billingProfile;
  final TeamSubscription? subscription;
  final List<String> enabledModules;
  final List<String> appliedPackageIds;

  TeamMember? get owner =>
      members.where((m) => m.userId == ownerId).firstOrNull;

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

  factory AdminTeam.fromJson(Map<dynamic, dynamic> map) {
    final members = (map['members'] as List<dynamic>? ?? const [])
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
    return AdminTeam(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      ownerId: (map['ownerId'] ?? '').toString(),
      members: members,
      memberCount: (map['memberCount'] as num?)?.toInt() ?? members.length,
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      billingProfile: map['billingProfile'] is Map
          ? BillingProfile.fromMap(
              Map<String, dynamic>.from(map['billingProfile'] as Map),
            )
          : null,
      subscription: TeamSubscription.fromMap(
        map['subscription'] is Map
            ? Map<String, dynamic>.from(map['subscription'] as Map)
            : null,
      ),
      enabledModules: ((map['enabledModules'] as List?) ?? const [])
          .map((module) => module.toString())
          .where(TeamExtraModule.all.contains)
          .toList(),
      appliedPackageIds: ((map['appliedPackageIds'] as List?) ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(),
    );
  }
}

class AdminRepository {
  AdminRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Stream<List<AdminTeam>> watchAllTeams() {
    final controller = StreamController<List<AdminTeam>>.broadcast();
    Timer? timer;

    Future<void> refresh() async {
      try {
        controller.add(await _fetchTeams());
      } catch (e) {
        controller.addError(e);
      }
    }

    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (controller.hasListener) unawaited(refresh());
    });
    controller.onCancel = () => timer?.cancel();
    return controller.stream;
  }

  Stream<List<Map<String, dynamic>>> watchAllUsers() {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    Timer? timer;

    Future<void> refresh() async {
      try {
        controller.add(await _fetchUsers());
      } catch (e) {
        controller.addError(e);
      }
    }

    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (controller.hasListener) unawaited(refresh());
    });
    controller.onCancel = () => timer?.cancel();
    return controller.stream;
  }

  Future<List<AdminTeam>> _fetchTeams() async {
    final raw = await _api.get('/app/admin_teams.php');
    final teams = (raw is Map ? raw['teams'] : null) as List? ?? const [];
    return teams
        .whereType<Map>()
        .map((team) => AdminTeam.fromJson(team))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Map<String, dynamic>>> _fetchUsers() async {
    final raw = await _api.get('/app/users.php');
    final users = (raw is Map ? raw['users'] : null) as List? ?? const [];
    return users.whereType<Map>().map((u) {
      final map = Map<String, dynamic>.from(u);
      map['teamId'] = map['teamId'] ?? '';
      return map;
    }).toList()..sort(
      (a, b) => (a['displayName'] as String? ?? '').compareTo(
        b['displayName'] as String? ?? '',
      ),
    );
  }

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
      return body['localId'] as String?;
    }

    final errorCode = (body['error'] as Map?)?['message'] as String? ?? '';
    if (errorCode.contains('EMAIL_EXISTS')) {
      throw Exception(
        'Email già presente in Firebase Auth. Per collegarla serve conoscere il suo UID oppure ricrearla da Firebase Console.',
      );
    }
    throw Exception('Errore creazione account Firebase: $errorCode');
  }

  Future<String> createTeam({
    required String name,
    required String ownerEmail,
    required String ownerDisplayName,
    required String ownerRole,
    required String ownerPassword,
  }) async {
    final newUid = await _createAuthUser(
      email: ownerEmail,
      password: ownerPassword,
    );
    if (newUid == null || newUid.isEmpty) {
      throw Exception('Impossibile creare account Firebase per $ownerEmail');
    }

    final raw = await _api.post('/app/admin_teams.php', {
      'action': 'createTeam',
      'teamName': name,
      'owner': {
        'userId': newUid,
        'email': ownerEmail,
        'displayName': ownerDisplayName,
        'role': ownerRole,
      },
    });
    return ((raw is Map ? raw['teamId'] : null) ?? '').toString();
  }

  Future<void> addMemberToTeam({
    required String teamId,
    required String email,
    required String displayName,
    required String role,
    required String password,
  }) async {
    final newUid = await _createAuthUser(email: email, password: password);
    if (newUid == null || newUid.isEmpty) {
      throw Exception('Impossibile creare account Firebase per $email');
    }

    await _api.post('/app/admin_teams.php', {
      'action': 'addMember',
      'teamId': teamId,
      'member': {
        'userId': newUid,
        'email': email,
        'displayName': displayName,
        'role': role,
        'status': 'active',
      },
    });
  }

  Future<void> removeMember({
    required String teamId,
    required String userId,
  }) async {
    await _api.delete(
      '/app/admin_teams.php',
      query: {'teamId': teamId, 'member': userId},
    );
  }

  Future<void> deleteTeam(String teamId) async {
    await _api.delete('/app/admin_teams.php', query: {'teamId': teamId});
  }

  Future<void> updateTeamName(String teamId, String name) async {
    await _api.put('/app/admin_teams.php', {'teamId': teamId, 'name': name});
  }

  Future<void> updateTeamBilling(String teamId, BillingProfile profile) async {
    await _api.put('/app/admin_teams.php', {
      'teamId': teamId,
      'billingProfile': profile.toMap(),
    });
  }

  Future<void> updateTeamSubscription(
    String teamId,
    TeamSubscription sub,
  ) async {
    await _api.put('/app/admin_teams.php', {
      'teamId': teamId,
      'subscription': sub.toMap(),
    });
  }

  Future<void> updateTeamModules(
    String teamId,
    List<String> enabledModules,
  ) async {
    await _api.put('/app/admin_teams.php', {
      'teamId': teamId,
      'enabledModules': enabledModules
          .where(TeamExtraModule.all.contains)
          .toSet()
          .toList(),
    });
  }

  Future<List<ConfigurationPackage>> listConfigurationPackages() async {
    final raw = await _api.get(
      '/app/admin_teams.php',
      query: {'packages': '1'},
    );
    final items = (raw is Map ? raw['packages'] : null) as List? ?? const [];
    return items
        .whereType<Map>()
        .map((item) => ConfigurationPackage.fromMap(item))
        .toList();
  }

  Future<void> applyConfigurationPackages(
    String teamId,
    List<String> packageIds,
  ) async {
    await _api.put('/app/admin_teams.php', {
      'teamId': teamId,
      'appliedPackageIds': packageIds,
    });
  }

  Future<void> saveConfigurationPackage(ConfigurationPackage package) async {
    await _api.post('/app/admin_teams.php', {
      'action': 'savePackage',
      'package': package.toMap(),
    });
  }

  Future<void> deleteConfigurationPackage(String packageId) async {
    await _api.post('/app/admin_teams.php', {
      'action': 'deletePackage',
      'packageId': packageId,
    });
  }

  Future<TeamSubscription> getTeamSubscription(String teamId) async {
    final raw = await _api.get('/app/admin_teams.php', query: {'id': teamId});
    final team = raw is Map ? raw['team'] : null;
    if (team is! Map) return TeamSubscription.fromMap(null);
    return TeamSubscription.fromMap(
      team['subscription'] is Map
          ? Map<String, dynamic>.from(team['subscription'] as Map)
          : null,
    );
  }

  Future<BillingProfile?> getTeamBilling(String teamId) async {
    final raw = await _api.get('/app/admin_teams.php', query: {'id': teamId});
    final team = raw is Map ? raw['team'] : null;
    if (team is! Map || team['billingProfile'] is! Map) return null;
    return BillingProfile.fromMap(
      Map<String, dynamic>.from(team['billingProfile'] as Map),
    );
  }

  Stream<BillingProfile> watchTeamBilling(String teamId) {
    return Stream.periodic(const Duration(seconds: 20))
        .asyncMap((_) => getTeamBilling(teamId))
        .map((profile) => profile ?? BillingProfile.empty);
  }

  Future<Map<String, dynamic>> getUserActivity(String userId) async {
    final raw = await _api.get(
      '/app/admin_teams.php',
      query: {'activityUserId': userId},
    );
    return raw is Map
        ? Map<String, dynamic>.from(raw['activity'] as Map? ?? const {})
        : const {};
  }
}
