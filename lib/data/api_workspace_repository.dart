import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/domain_models.dart';
import 'api_client.dart';
import 'workspace_snapshot.dart';

export 'workspace_snapshot.dart';

// Converte ricorsivamente una mappa Firestore in JSON-safe:
// Timestamp → ISO string, DateTime → ISO string, nested maps/lists inclusi.
Map<String, dynamic> _jsonSafe(Map<String, dynamic> map) {
  return map.map((k, v) => MapEntry(k, _toJsonValue(v)));
}

dynamic _toJsonValue(dynamic v) {
  if (v is Timestamp) return v.toDate().toIso8601String();
  if (v is DateTime) return v.toIso8601String();
  if (v is FieldValue)
    return DateTime.now().toIso8601String(); // serverTimestamp → now
  if (v is Map) return _jsonSafe(Map<String, dynamic>.from(v));
  if (v is List) return v.map(_toJsonValue).toList();
  return v;
}

// ─────────────────────────────────────────────────────────────────────────────
// ApiWorkspaceRepository
// Sostituisce ApiWorkspaceRepository con chiamate REST all'API PHP.
// watchWorkspace() simula il real-time con polling ogni 30 secondi.
// ─────────────────────────────────────────────────────────────────────────────

class ApiWorkspaceRepository {
  ApiWorkspaceRepository({ApiClient? client})
    : _api = client ?? ApiClient.instance;

  final ApiClient _api;

  // ── Workspace stream (polling) ────────────────────────────────────────────
  StreamController<WorkspaceSnapshot>? _workspaceCtrl;
  Timer? _pollTimer;
  String? _lastUserId;

  // taskLimit ignorato — SQL non ha limiti fissi come Firestore
  Stream<WorkspaceSnapshot> watchWorkspace(
    String userId, {
    int taskLimit = 120,
  }) {
    if (_lastUserId != userId) {
      _stopPolling();
    }
    _lastUserId = userId;

    if (_workspaceCtrl == null || _workspaceCtrl!.isClosed) {
      _workspaceCtrl = StreamController<WorkspaceSnapshot>.broadcast();
      _startPolling(userId);
    }
    return _workspaceCtrl!.stream;
  }

  void _startPolling(String userId) {
    // Primo fetch — ApiClient._ensureAuth() gestisce internamente il timing
    _fetchAndEmit(userId);
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchAndEmit(userId);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _workspaceCtrl?.close();
    _workspaceCtrl = null;
  }

  void invalidateCache() {
    if (_lastUserId != null) _fetchAndEmit(_lastUserId!);
  }

  Future<void> _fetchAndEmit(String userId) async {
    try {
      final raw =
          await _api.get('/workspace/index.php') as Map<String, dynamic>;
      final snapshot = _parseWorkspace(raw);
      _workspaceCtrl?.add(snapshot);
    } catch (e, st) {
      // Loggato in console — non chiude lo stream, riprova al prossimo poll
      // ignore: avoid_print
      print('[ApiWorkspaceRepository] fetchAndEmit error: $e\n$st');
    }
  }

  // ── Parse WorkspaceSnapshot dal JSON ─────────────────────────────────────
  WorkspaceSnapshot _parseWorkspace(Map<String, dynamic> raw) {
    return WorkspaceSnapshot(
      companies: _list(raw['companies'], Company.fromMap),
      companyContacts: _list(raw['companyContacts'], CompanyContact.fromMap),
      opportunities: _list(
        raw['opportunities'],
        (id, m) => Opportunity.fromMap(id, m),
      ),
      gussoniQuotations: _list(
        raw['gussoniQuotations'],
        (id, m) => Preventivo.fromMap(id, m),
      ),
      projects: _list(raw['projects'], (id, m) => Project.fromMap(id, m)),
      phases: _list(raw['phases'], (id, m) => ProjectPhase.fromMap(id, m)),
      tasks: _list(raw['tasks'], (id, m) => WorkTask.fromMap(id, m)),
      plannedSlots: _list(
        raw['plannedSlots'],
        (id, m) => TimelineSlot.fromMap(id, m),
      ),
      timeTracks: _list(raw['timeTracks'], (id, m) => TimeTrack.fromMap(id, m)),
      invoiceDrafts: _list(
        raw['invoiceDrafts'],
        (id, m) => InvoiceDraft.fromMap(id, m),
      ),
      tickets: _list(raw['tickets'], (id, m) => Ticket.fromMap(id, m)),
      availability: _parseAvailability(raw['availability']),
      vacations: _list(
        raw['vacations'],
        (id, m) => VacationPeriod.fromMap(id, m),
      ),
      billingProfile: _parseBillingProfile(raw['billingProfile']),
      emailSignatureHtml: raw['emailSignatureHtml'] as String? ?? '',
      youdoxConfig: YouDoxConfig.fromMap(
        (raw['youdoxConfig'] as Map<String, dynamic>?) ?? {},
      ),
    );
  }

  List<T> _list<T>(
    dynamic rawList,
    T Function(String id, Map<String, dynamic> m) fromMap,
  ) {
    if (rawList == null || rawList is! List) return [];
    final result = <T>[];
    for (final item in rawList) {
      try {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        result.add(fromMap((m['id'] as String?) ?? '', m));
      } catch (e) {
        // ignore: avoid_print
        print('[ApiWorkspaceRepository] _list parse error: $e  item=$item');
      }
    }
    return result;
  }

  List<UserAvailability> _parseAvailability(dynamic raw) {
    if (raw == null) return [];
    return (raw as List).map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      return UserAvailability(
        weekday: (m['weekday'] as num).toInt(),
        hours: (m['hours'] as num).toDouble(),
        isOff: m['isOff'] == true || m['isOff'] == 1,
      );
    }).toList();
  }

  BillingProfile _parseBillingProfile(dynamic raw) {
    if (raw == null || raw is! Map) return BillingProfile.empty;
    return BillingProfile.fromMap(Map<String, dynamic>.from(raw));
  }

  // ── Companies ─────────────────────────────────────────────────────────────
  Future<void> createCompany(String userId, Company company) async {
    await _api.post(
      '/companies/index.php',
      _jsonSafe(company.toMap())..['id'] = company.id,
    );
    invalidateCache();
  }

  Future<void> updateCompany(String userId, Company company) async {
    await _api.put(
      '/companies/index.php',
      _jsonSafe(company.toMap()),
      query: {'id': company.id},
    );
    invalidateCache();
  }

  Future<void> deleteCompanyContact(String userId, String contactId) async {
    await _api.delete('/contacts/index.php', query: {'id': contactId});
    invalidateCache();
  }

  Future<void> createCompanyContact(
    String userId,
    CompanyContact contact,
  ) async {
    await _api.post(
      '/contacts/index.php',
      _jsonSafe(contact.toMap())..['id'] = contact.id,
    );
    invalidateCache();
  }

  Future<void> updateCompanyContact(
    String userId,
    CompanyContact contact,
  ) async {
    await _api.put(
      '/contacts/index.php',
      _jsonSafe(contact.toMap()),
      query: {'id': contact.id},
    );
    invalidateCache();
  }

  // ── Opportunities ─────────────────────────────────────────────────────────
  Future<String> createOpportunity(String userId, Opportunity opp) async {
    final id = opp.id.isEmpty ? _tempId('opp') : opp.id;
    await _api.post(
      '/opportunities/index.php',
      _jsonSafe({...opp.toMap(), 'id': id}),
    );
    invalidateCache();
    return id;
  }

  Future<void> updateOpportunity(String userId, Opportunity opp) async {
    await _api.put(
      '/opportunities/index.php',
      _jsonSafe(opp.toMap()),
      query: {'id': opp.id},
    );
    invalidateCache();
  }

  Future<void> deleteOpportunity(String userId, String id) async {
    await _api.delete('/opportunities/index.php', query: {'id': id});
    invalidateCache();
  }

  // ── Preventivi ────────────────────────────────────────────────────────────
  Future<String> createGussoniQuotation(String userId, Preventivo q) async {
    final id = q.id.isEmpty ? _tempId('quot') : q.id;
    await _api.post('/preventivi/index.php', {
      ..._preventivoToMap(q),
      'id': id,
    });
    invalidateCache();
    return id;
  }

  Future<void> updateGussoniQuotation(String userId, Preventivo q) async {
    await _api.put(
      '/preventivi/index.php',
      _preventivoToMap(q),
      query: {'id': q.id},
    );
    invalidateCache();
  }

  Future<void> deleteGussoniQuotation(String userId, String id) async {
    await _api.delete('/preventivi/index.php', query: {'id': id});
    invalidateCache();
  }

  Future<void> acceptGussoniQuotation(
    String userId,
    String quotationId,
    String? opportunityId,
  ) async {
    await _api.post('/preventivi/index.php?id=$quotationId&action=accept', {
      'opportunityId': opportunityId,
    });
    invalidateCache();
  }

  // ── Projects ──────────────────────────────────────────────────────────────
  Future<void> createProject(String userId, Project project) async {
    await _api.post('/projects/index.php', _projectToMap(project));
    invalidateCache();
  }

  Future<void> updateProject(String userId, Project project) async {
    await _api.put(
      '/projects/index.php',
      _projectToMap(project),
      query: {'id': project.id},
    );
    invalidateCache();
  }

  Future<void> setAnticipoEmesso(String userId, String projectId) async {
    await _api.post(
      '/projects/index.php?id=$projectId&action=set_anticipo_emesso',
      {},
    );
    invalidateCache();
  }

  Future<String> createProjectWithConfig({
    required String userId,
    required String name,
    required String companyId,
    required List<PhaseConfig> phaseConfigs,
    String? projectId,
    ProjectType type = ProjectType.profit,
    String? opportunityId,
    String? quotationId,
  }) async {
    final resp = await _api.post(
      '/projects/index.php?action=create_with_config',
      {
        'id': projectId,
        'name': name,
        'companyId': companyId,
        'type': type.name,
        'opportunityId': opportunityId,
        'quotationId': quotationId,
        'phaseConfigs': phaseConfigs
            .map(
              (c) => {
                'phaseName': c.phaseName,
                'taskNames': c.taskNames,
                'startDate': c.startDate?.toIso8601String(),
                'endDate': c.endDate?.toIso8601String(),
                'assigneeId': c.assigneeId,
              },
            )
            .toList(),
      },
    );
    invalidateCache();
    return resp['id'] as String;
  }

  // ── Phases ────────────────────────────────────────────────────────────────
  Future<void> createPhase(String userId, ProjectPhase phase) async {
    await _api.post('/phases/index.php', {
      'id': phase.id,
      'projectId': phase.projectId,
      'name': phase.name,
      'order': phase.order,
      'status': phase.status.name,
      'assignedUserId': phase.assignedUserId,
      'startDate': phase.startDate?.toIso8601String(),
      'deadline': phase.deadline?.toIso8601String(),
      'notes': phase.notes,
      'isCustom': phase.isCustom,
    });
    invalidateCache();
  }

  Future<void> updatePhase(String userId, ProjectPhase phase) async {
    await _api.put(
      '/phases/index.php',
      {
        'name': phase.name,
        'status': phase.status.name,
        'assignedUserId': phase.assignedUserId,
        'deadline': phase.deadline?.toIso8601String(),
        'startDate': phase.startDate?.toIso8601String(),
        'notes': phase.notes,
      },
      query: {'id': phase.id},
    );
    invalidateCache();
  }

  Future<void> updatePhasePlanning(String userId, ProjectPhase phase) async {
    await _api.put(
      '/phases/index.php',
      {
        'name': phase.name,
        'status': phase.status.name,
        'assignedUserId': phase.assignedUserId,
        'deadline': phase.deadline?.toIso8601String(),
        'startDate': phase.startDate?.toIso8601String(),
        'notes': phase.notes,
        'syncTasks': true,
      },
      query: {'id': phase.id},
    );
    invalidateCache();
  }

  Future<void> updatePhaseStatus(
    String userId,
    String phaseId,
    PhaseStatus status,
  ) async {
    await _api.put(
      '/phases/index.php',
      {'status': status.name},
      query: {'id': phaseId},
    );
    invalidateCache();
  }

  Future<void> assignPhase(
    String userId,
    String phaseId,
    String? assignedUserId,
    DateTime? deadline,
  ) async {
    await _api.put(
      '/phases/index.php',
      {
        'assignedUserId': assignedUserId,
        'deadline': deadline?.toIso8601String(),
      },
      query: {'id': phaseId},
    );
    invalidateCache();
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────
  Future<void> createTask(String userId, WorkTask task) async {
    await _api.post('/tasks/index.php', _taskToMap(task));
    invalidateCache();
  }

  Future<void> updateTask(String userId, WorkTask task) async {
    await _api.put(
      '/tasks/index.php',
      _taskToMap(task),
      query: {'id': task.id},
    );
    invalidateCache();
  }

  Future<void> deleteTask(String userId, String taskId) async {
    await _api.delete('/tasks/index.php', query: {'id': taskId});
    invalidateCache();
  }

  // ── Task Comments ─────────────────────────────────────────────────────────
  Future<void> createTaskComment(String userId, TaskComment comment) async {
    await _api.post('/tasks/comments.php', {
      'id': comment.id,
      'taskId': comment.taskId,
      'authorId': comment.authorId,
      'authorName': comment.authorName,
      'body': comment.body,
    });
  }

  Future<void> deleteTaskComment(String userId, String commentId) async {
    await _api.delete('/tasks/comments.php', query: {'id': commentId});
  }

  Stream<List<TaskComment>> watchTaskComments(String userId, String taskId) {
    final ctrl = StreamController<List<TaskComment>>.broadcast();
    void fetch() async {
      try {
        final raw =
            await _api.get('/tasks/comments.php', query: {'task_id': taskId})
                as List;
        final comments = raw.map((item) {
          final m = Map<String, dynamic>.from(item as Map);
          return TaskComment(
            id: m['id'] as String? ?? '',
            taskId: m['task_id'] as String? ?? taskId,
            authorId: m['author_id'] as String? ?? '',
            authorName: m['author_name'] as String? ?? '',
            body: m['body'] as String? ?? '',
            createdAt: m['created_at'] != null
                ? (DateTime.tryParse(m['created_at'] as String) ??
                      DateTime.now())
                : DateTime.now(),
          );
        }).toList();
        ctrl.add(comments);
      } catch (_) {}
    }

    fetch();
    final timer = Timer.periodic(const Duration(seconds: 15), (_) => fetch());
    ctrl.onCancel = () => timer.cancel();
    return ctrl.stream;
  }

  // ── Invoices ──────────────────────────────────────────────────────────────
  Future<void> saveInvoice(
    String userId, {
    required InvoiceDraft invoice,
    Map<String, dynamic> details = const {},
  }) async {
    // `details` sono metadati extra (XML, Youdox, ecc.) — memorizzati nelle note per ora
    await _api.post('/invoices/index.php', {
      ..._invoiceToMap(invoice),
      if (details.isNotEmpty) 'extraDetails': details,
    });
    invalidateCache();
  }

  Future<void> deleteInvoice(String userId, String invoiceId) async {
    await _api.delete('/invoices/index.php', query: {'id': invoiceId});
    invalidateCache();
  }

  // ── Time Tracks ───────────────────────────────────────────────────────────
  Future<void> createTimeTrack(String userId, TimeTrack track) async {
    await _api.post('/time-tracks/index.php', _trackToMap(track, userId));
    invalidateCache();
  }

  Future<void> updateTimeTrack(String userId, TimeTrack track) async {
    await _api.put(
      '/time-tracks/index.php',
      _trackToMap(track, userId),
      query: {'id': track.id},
    );
    invalidateCache();
  }

  Future<void> deleteTimeTrack(String userId, String trackId) async {
    await _api.delete('/time-tracks/index.php', query: {'id': trackId});
    invalidateCache();
  }

  // ── Serialization helpers ─────────────────────────────────────────────────

  Map<String, dynamic> _preventivoToMap(Preventivo q) => {
    'opportunityId': q.opportunityId,
    'companyId': q.companyId,
    'status': q.status.name,
    'lines': q.lines
        .map(
          (l) => {
            'description': l.description,
            'quantity': l.quantity,
            'unitPrice': l.unitPrice,
          },
        )
        .toList(),
    'istruttoriaFee': q.istruttoriaFee,
    'successFeePercent': q.successFeePercent,
    'notes': q.notes,
    'sentAt': q.sentAt?.toIso8601String(),
  };

  Map<String, dynamic> _projectToMap(Project p) => {
    'id': p.id,
    'companyId': p.companyId,
    'name': p.name,
    'code': p.code,
    'status': p.status,
    'type': p.type.name,
    'opportunityId': p.opportunityId,
    'quotationId': p.quotationId,
    'notes': p.notes,
    'anticipoEmesso': p.anticipoEmesso,
    'rifProgetto': p.rifProgetto,
    'grantAmount': p.grantAmount,
    'successFeeAmount': p.successFeeAmount,
  };

  Map<String, dynamic> _taskToMap(WorkTask t) => {
    'id': t.id,
    'companyId': t.companyId,
    'projectId': t.projectId,
    'phaseId': t.phaseId,
    'assigneeId': t.assigneeId,
    'name': t.name,
    'estimatedHours': t.estimatedHours,
    'loggedHours': t.loggedHours,
    'startDate': t.startDate.toIso8601String(),
    'deadline': t.deadline.toIso8601String(),
    'status': t.status.name,
    'billable': t.billable,
    'description': '',
  };

  Map<String, dynamic> _invoiceToMap(InvoiceDraft i) => {
    'id': i.id,
    'companyId': i.companyId,
    'number': i.number,
    'amount': i.amount,
    'status': i.status.name,
    'projectId': i.projectId,
    'lines': i.lines
        .map(
          (l) => {
            'description': l.description,
            'quantity': l.quantity,
            'unitPrice': l.unitPrice,
            'vatPercent': l.vatPercent,
          },
        )
        .toList(),
    'isSuccessFee': i.isSuccessFee,
    'grantAmount': i.grantAmount,
    'notes': i.notes,
    'sentAt': i.sentAt?.toIso8601String(),
    'createdAt': i.createdAt?.toIso8601String(),
  };

  Map<String, dynamic> _trackToMap(TimeTrack t, String userId) => {
    'id': t.id,
    'taskId': t.taskId,
    'name': t.name,
    'companyId': t.companyId,
    'projectId': t.projectId,
    'startAt': t.startAt.toIso8601String(),
    'endAt': t.endAt.toIso8601String(),
    'userId': t.userId,
    'description': t.description,
    'billable': t.billable,
    'tipo': t.tipo,
    'hourlyRate': t.hourlyRate,
  };

  // ── Timeline slots ────────────────────────────────────────────────────────
  Future<void> updateTimelineSlot(String userId, TimelineSlot slot) async {
    await _api.put(
      '/timeline-slots/index.php',
      {
        'taskId': slot.taskId,
        'slotDate': slot.date.toIso8601String().substring(0, 10),
        'plannedHours': slot.plannedHours,
        'startHour': slot.startHour,
      },
      query: {'id': slot.id},
    );
    invalidateCache();
  }

  Future<void> deleteTimelineSlot(String userId, String slotId) async {
    await _api.delete('/timeline-slots/index.php', query: {'id': slotId});
    invalidateCache();
  }

  Future<void> upsertTimelineSlots(
    String userId,
    List<TimelineSlot> slots,
  ) async {
    await _api.post('/timeline-slots/index.php?action=upsert', {
      'slots': slots
          .map(
            (s) => {
              'id': s.id,
              'taskId': s.taskId,
              'slotDate': s.date.toIso8601String().substring(0, 10),
              'plannedHours': s.plannedHours,
              'startHour': s.startHour,
            },
          )
          .toList(),
    });
    invalidateCache();
  }

  Future<void> replaceTimelineSlotsForTask(
    String userId, {
    required String taskId,
    required List<TimelineSlot> slots,
  }) async {
    await _api.post('/timeline-slots/index.php?action=replace_for_task', {
      'taskId': taskId,
      'slots': slots
          .map(
            (s) => {
              'id': s.id,
              'taskId': s.taskId,
              'slotDate': s.date.toIso8601String().substring(0, 10),
              'plannedHours': s.plannedHours,
              'startHour': s.startHour,
            },
          )
          .toList(),
    });
    invalidateCache();
  }

  Future<void> replaceTimelineSlots(
    String userId,
    List<TimelineSlot> slots,
  ) async {
    await _api.post('/timeline-slots/index.php?action=replace_all', {
      'slots': slots
          .map(
            (s) => {
              'id': s.id,
              'taskId': s.taskId,
              'slotDate': s.date.toIso8601String().substring(0, 10),
              'plannedHours': s.plannedHours,
              'startHour': s.startHour,
            },
          )
          .toList(),
    });
    invalidateCache();
  }

  Future<void> removeTimelineSlotsForTask(String userId, String taskId) async {
    await _api.delete('/timeline-slots/index.php', query: {'task_id': taskId});
    invalidateCache();
  }

  // ── Vacations ─────────────────────────────────────────────────────────────
  Future<void> createVacation(String userId, VacationPeriod vacation) async {
    await _api.post('/misc/index.php?entity=vacations', {
      'id': vacation.id,
      'startDate': vacation.startDate.toIso8601String().substring(0, 10),
      'endDate': vacation.endDate.toIso8601String().substring(0, 10),
      'label': vacation.label,
    });
    invalidateCache();
  }

  Future<void> deleteVacation(String userId, String vacationId) async {
    await _api.delete(
      '/misc/index.php?entity=vacations',
      query: {'id': vacationId},
    );
    invalidateCache();
  }

  // ── Availability ──────────────────────────────────────────────────────────
  Future<void> updateAvailability(String userId, UserAvailability entry) async {
    await _api.post('/misc/index.php?entity=availability', {
      'weekday': entry.weekday,
      'hours': entry.hours,
      'isOff': entry.isOff,
    });
    invalidateCache();
  }

  // ── Tickets ───────────────────────────────────────────────────────────────
  Future<void> createTicket(String userId, Ticket ticket) async {
    await _api.post('/misc/index.php?entity=tickets', {
      'id': ticket.id,
      'companyId': ticket.companyId,
      'title': ticket.title,
      'recipientEmail': ticket.recipientEmail,
      'status': ticket.status.name,
      'entries': ticket.entries.map((e) => _jsonSafe(e.toMap())).toList(),
    });
    invalidateCache();
  }

  Future<void> updateTicket(String userId, Ticket ticket) async {
    await _api.put(
      '/misc/index.php?entity=tickets',
      {
        'status': ticket.status.name,
        'entries': ticket.entries.map((e) => _jsonSafe(e.toMap())).toList(),
      },
      query: {'id': ticket.id},
    );
    invalidateCache();
  }

  Future<void> deleteTicket(String userId, String ticketId) async {
    await _api.delete(
      '/misc/index.php?entity=tickets',
      query: {'id': ticketId},
    );
    invalidateCache();
  }

  // ── Billing Profile ───────────────────────────────────────────────────────
  Future<void> updateBillingProfile(
    String userId,
    BillingProfile profile,
  ) async {
    await _api.put(
      '/misc/index.php?entity=billing_profile',
      _jsonSafe(profile.toMap()),
    );
    invalidateCache();
  }

  // ── Youdox Config ─────────────────────────────────────────────────────────
  Future<void> updateYoudoxConfig(String userId, YouDoxConfig config) async {
    await _api.put(
      '/misc/index.php?entity=youdox_config',
      _jsonSafe(config.toMap()),
    );
    invalidateCache();
  }

  Future<YouDoxConfig> getYoudoxConfig(String userId) async {
    try {
      final raw = await _api.get('/misc/index.php?entity=youdox_config');
      return YouDoxConfig.fromMap((raw as Map<String, dynamic>?) ?? {});
    } catch (_) {
      return YouDoxConfig.empty;
    }
  }

  // ── Email signature ───────────────────────────────────────────────────────
  Future<void> updateEmailSignatureHtml(String userId, String html) async {
    await _api.put('/misc/index.php?entity=email_signature', {'html': html});
    invalidateCache();
  }

  // ── User UI state ─────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getUserUiState(String userId) async {
    try {
      final raw = await _api.get('/misc/index.php?entity=ui_state');
      return (raw as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> saveUserUiState(
    String userId, {
    required int selectedIndex,
    required int todoSub,
    required int finanzeSub,
  }) async {
    try {
      await _api.put('/misc/index.php?entity=ui_state', {
        'selectedIndex': selectedIndex,
        'todoSub': todoSub,
        'finanzeSub': finanzeSub,
      });
    } catch (_) {}
  }

  // ── Tasks: delete backlog ─────────────────────────────────────────────────
  Future<void> deleteBacklogTasks(String userId) async {
    await _api.delete('/tasks/index.php?action=delete_backlog');
    invalidateCache();
  }

  // ── Invoice details (extended) ────────────────────────────────────────────
  Future<Map<String, dynamic>?> getInvoiceDetails(
    String userId,
    String invoiceId,
  ) async {
    try {
      final raw = await _api.get(
        '/invoices/index.php',
        query: {'id': invoiceId, 'details': '1'},
      );
      return raw as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ── Project: create from quotation (vecchio flusso) ───────────────────────
  Future<String> createProjectFromQuotation({
    required String userId,
    required String name,
    required String companyId,
    required String opportunityId,
    required String quotationId,
    required ProjectType type,
  }) async {
    // Usa create_with_config senza fasi (fasi vuote — wizard non invocato)
    final resp = await _api
        .post('/projects/index.php?action=create_with_config', {
          'name': name,
          'companyId': companyId,
          'type': type.name,
          'opportunityId': opportunityId,
          'quotationId': quotationId,
          'phaseConfigs': [],
        });
    invalidateCache();
    return resp['id'] as String;
  }

  // ── closeProjectWithInvoice ───────────────────────────────────────────────
  Future<void> closeProjectWithInvoice({
    required String userId,
    required Project project,
    required double grantAmount,
  }) async {
    final updatedProject = project.copyWith(
      status: 'closed',
      closedAt: DateTime.now(),
      grantAmount: grantAmount,
    );
    await updateProject(userId, updatedProject);
    final invoiceId = _tempId('inv-close');
    final draft = InvoiceDraft(
      id: invoiceId,
      companyId: project.companyId,
      projectId: project.id,
      number: 'BOZZA-CLOSE',
      amount: grantAmount,
      status: InvoiceStatus.draft,
      isSuccessFee: true,
      grantAmount: grantAmount,
      notes: 'Premialità finale — ${project.name}',
      createdAt: DateTime.now(),
      lines: [
        InvoiceLine(
          description: 'Premialità finale',
          quantity: 1,
          unitPrice: grantAmount,
        ),
      ],
    );
    await saveInvoice(userId, invoice: draft);
    invalidateCache();
  }

  // ── upsertPushToken (stub – FCM è ancora Firebase) ────────────────────────
  Future<void> upsertPushToken(
    String userId, {
    required String token,
    required String platform,
  }) async {}

  // ── Google Calendar (stub – non migrato su SQL) ────────────────────────────
  Future<Map<String, String>> getGoogleCalendarSlotEventMap(
    String userId,
  ) async => {};
  Future<void> setGoogleCalendarSlotEvent(
    String userId, {
    required String slotId,
    required String eventId,
  }) async {}
  Future<void> deleteGoogleCalendarSlotEvent(
    String userId, {
    required String slotId,
  }) async {}

  // ── Seed (no-op su SQL – i dati si inseriscono tramite API) ───────────────
  Future<void> seedWorkspace(String userId) async {}

  String _tempId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  void dispose() => _stopPolling();
}
