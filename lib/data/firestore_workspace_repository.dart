import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/domain_models.dart';
import 'sample_data.dart';
import 'workspace_snapshot.dart';

export 'workspace_snapshot.dart';

class FirestoreWorkspaceRepository {
  FirestoreWorkspaceRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const int _taskLookbackDays = 90;
  static const int _maxTaskDocs = 300;
  static const int _slotLookbackDays = 14;   // slot passati: 2 settimane
  static const int _slotForwardDays = 60;    // slot futuri: 2 mesi
  static const int _timeTrackLookbackDays = 90;
  static const int _maxTimeTrackDocs = 500;
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _actionAt(
    Map<String, dynamic> data, {
    List<String> orderedKeys = const ['updatedAt', 'createdAt'],
    DateTime? fallback,
  }) {
    for (final key in orderedKeys) {
      final raw = data[key];
      if (raw is Timestamp || raw is DateTime) {
        return parseDate(raw);
      }
      if (raw is String && raw.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return fallback ?? _epoch;
  }

  CollectionReference<Map<String, dynamic>> _userCollection(
    String userId,
    String name,
  ) {
    return _firestore.collection('users').doc(userId).collection(name);
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) {
    return _firestore.collection('users').doc(userId);
  }

  Stream<WorkspaceSnapshot> watchWorkspace(
    String userId, {
    int taskLimit = 120,
  }) {
    final controller = StreamController<WorkspaceSnapshot>();
    final taskCutoffDate = DateTime.now().subtract(
      const Duration(days: _taskLookbackDays),
    );

    var companies = <Company>[];
    var companyContacts = <CompanyContact>[];
    var tickets = <Ticket>[];
    var projects = <Project>[];
    var phases = <ProjectPhase>[];
    var tasks = <WorkTask>[];
    var availability = <UserAvailability>[];
    var vacations = <VacationPeriod>[];
    var slots = <TimelineSlot>[];
    var timeTracks = <TimeTrack>[];
    var invoices = <InvoiceDraft>[];
    var billingProfile = BillingProfile.empty;
    var emailSignatureHtml = '';
    var youdoxConfig = YouDoxConfig.empty;
    var opportunities = <Opportunity>[];
    var gussoniQuotations = <Preventivo>[];
    // Stream separato per il billing del team — evita get() ad ogni emit
    String? _cachedTeamId;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _teamBillingSub;

    void emit() {
      if (controller.isClosed) {
        return;
      }
      controller.add(
        WorkspaceSnapshot(
          companies: [...companies],
          companyContacts: [...companyContacts],
          tickets: [...tickets],
          projects: [...projects],
          phases: [...phases],
          tasks: [...tasks],
          availability: [...availability],
          vacations: [...vacations],
          plannedSlots: [...slots],
          timeTracks: [...timeTracks],
          invoiceDrafts: [...invoices],
          billingProfile: billingProfile,
          emailSignatureHtml: emailSignatureHtml,
          youdoxConfig: youdoxConfig,
          opportunities: [...opportunities],
          gussoniQuotations: [...gussoniQuotations],
        ),
      );
    }

    void emitError(Object error, StackTrace stackTrace) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }

    emit();

    final subscriptions = <StreamSubscription<dynamic>>[
      _userCollection(userId, 'companies').snapshots().listen((snapshot) {
        final docs = snapshot.docs.toList()
          ..sort((a, b) {
            final byAction = _actionAt(b.data()).compareTo(_actionAt(a.data()));
            if (byAction != 0) {
              return byAction;
            }
            final byName = (a.data()['name'] as String? ?? '').compareTo(
              b.data()['name'] as String? ?? '',
            );
            if (byName != 0) {
              return byName;
            }
            return a.id.compareTo(b.id);
          });
        companies = docs
            .map((doc) => Company.fromMap(doc.id, doc.data()))
            .toList();
        emit();
      }, onError: emitError),
      _userCollection(userId, 'companyContacts').snapshots().listen((snapshot) {
        final docs = snapshot.docs.toList()
          ..sort((a, b) {
            final byAction = _actionAt(b.data()).compareTo(_actionAt(a.data()));
            if (byAction != 0) {
              return byAction;
            }
            final byName = (a.data()['name'] as String? ?? '').compareTo(
              b.data()['name'] as String? ?? '',
            );
            if (byName != 0) {
              return byName;
            }
            return a.id.compareTo(b.id);
          });
        companyContacts = docs
            .map((doc) => CompanyContact.fromMap(doc.id, doc.data()))
            .toList();
        emit();
      }, onError: emitError),
      _userCollection(userId, 'tickets').snapshots().listen((snapshot) {
        tickets =
            snapshot.docs
                .map((doc) => Ticket.fromMap(doc.id, doc.data()))
                .toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        emit();
      }, onError: emitError),
      _userCollection(userId, 'projects').snapshots().listen((snapshot) {
        final docs = snapshot.docs.toList()
          ..sort((a, b) {
            final byAction = _actionAt(b.data()).compareTo(_actionAt(a.data()));
            if (byAction != 0) {
              return byAction;
            }
            final byName = (a.data()['name'] as String? ?? '').compareTo(
              b.data()['name'] as String? ?? '',
            );
            if (byName != 0) {
              return byName;
            }
            return a.id.compareTo(b.id);
          });
        projects = docs
            .map((doc) => Project.fromMap(doc.id, doc.data()))
            .toList();
        emit();
      }, onError: emitError),
      _userCollection(userId, 'phases').snapshots().listen((snapshot) {
        phases =
            snapshot.docs
                .map((doc) => ProjectPhase.fromMap(doc.id, doc.data()))
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order));
        emit();
      }, onError: emitError),
      _userCollection(userId, 'tasks')
          .orderBy('deadline', descending: true)
          .limit(taskLimit.clamp(20, _maxTaskDocs))
          .snapshots()
          .listen((snapshot) {
            final docs = snapshot.docs.toList()
              ..sort((a, b) {
                final aData = a.data();
                final bData = b.data();
                final byAction =
                    _actionAt(
                      bData,
                      orderedKeys: const [
                        'updatedAt',
                        'createdAt',
                        'startDate',
                        'deadline',
                      ],
                    ).compareTo(
                      _actionAt(
                        aData,
                        orderedKeys: const [
                          'updatedAt',
                          'createdAt',
                          'startDate',
                          'deadline',
                        ],
                      ),
                    );
                if (byAction != 0) {
                  return byAction;
                }
                final byName = (aData['name'] as String? ?? '').compareTo(
                  bData['name'] as String? ?? '',
                );
                if (byName != 0) {
                  return byName;
                }
                return a.id.compareTo(b.id);
              });
            tasks = docs
                .map((doc) => WorkTask.fromMap(doc.id, doc.data()))
                .where(
                  (task) =>
                      (task.status == TaskStatus.planned ||
                          task.status == TaskStatus.inProgress) &&
                      !task.deadline.isBefore(taskCutoffDate),
                )
                .toList();
            emit();
          }, onError: emitError),
      _userCollection(userId, 'availability').snapshots().listen((snapshot) {
        availability =
            snapshot.docs
                .map((doc) => UserAvailability.fromMap(doc.id, doc.data()))
                .toList()
              ..sort((a, b) => a.weekday.compareTo(b.weekday));
        emit();
      }, onError: emitError),
      _userCollection(userId, 'vacations').snapshots().listen((snapshot) {
        vacations =
            snapshot.docs
                .map((doc) => VacationPeriod.fromMap(doc.id, doc.data()))
                .toList()
              ..sort((a, b) => a.startDate.compareTo(b.startDate));
        emit();
      }, onError: emitError),
      _userCollection(userId, 'timelineSlots')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: _slotLookbackDays)),
            ),
          )
          .where(
            'date',
            isLessThanOrEqualTo: Timestamp.fromDate(
              DateTime.now().add(const Duration(days: _slotForwardDays)),
            ),
          )
          .orderBy('date')
          .snapshots()
          .listen((snapshot) {
            slots =
                snapshot.docs
                    .map((doc) => TimelineSlot.fromMap(doc.id, doc.data()))
                    .toList()
                  ..sort((a, b) => a.date.compareTo(b.date));
            emit();
          }, onError: emitError),
      _userCollection(userId, 'timeTracks')
          .where(
            'startAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(
              DateTime.now().subtract(
                const Duration(days: _timeTrackLookbackDays),
              ),
            ),
          )
          .orderBy('startAt', descending: true)
          .limit(_maxTimeTrackDocs)
          .snapshots()
          .listen((snapshot) {
            timeTracks =
                snapshot.docs
                    .map((doc) => TimeTrack.fromMap(doc.id, doc.data()))
                    .toList()
                  ..sort((a, b) => a.startAt.compareTo(b.startAt));
            emit();
          }, onError: emitError),
      _userCollection(userId, 'invoices').snapshots().listen((snapshot) {
        invoices =
            snapshot.docs
                .map((doc) => InvoiceDraft.fromMap(doc.id, doc.data()))
                .toList()
              ..sort((a, b) => a.number.compareTo(b.number));
        emit();
      }, onError: emitError),
      // ── Gussoni: Opportunità ──
      _userCollection(userId, 'opportunities').snapshots().listen((snapshot) {
        opportunities = snapshot.docs
            .map((doc) => Opportunity.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        emit();
      }, onError: emitError),
      // ── Gussoni: Preventiviì ──
      _userCollection(userId, 'gussoniQuotations').snapshots().listen((snapshot) {
        gussoniQuotations = snapshot.docs
            .map((doc) => Preventivo.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        emit();
      }, onError: emitError),
      // Profilo utente: emailSignature + teamId
      _userDoc(userId).snapshots().listen((snapshot) {
        final data = snapshot.data();
        emailSignatureHtml = (data?['emailSignatureHtml'] as String? ?? '')
            .trim();
        final teamId = data?['teamId'] as String?;

        if (teamId == null) {
          // Nessun team → billing personale (legacy), nessuna read extra
          billingProfile = BillingProfile.fromMap(
            data?['billingProfile'] as Map<String, dynamic>?,
          );
          youdoxConfig = YouDoxConfig.fromMap(
            data?['youdoxConfig'] as Map<String, dynamic>?,
          );
          emit();
          return;
        }

        // Team trovato → apri il listener del team SOLO se è cambiato il teamId
        // Evita di rifare la read ad ogni emit del documento utente
        if (teamId != _cachedTeamId) {
          _cachedTeamId = teamId;
          _teamBillingSub?.cancel();
          _teamBillingSub = _firestore
              .collection('teams')
              .doc(teamId)
              .snapshots()
              .listen((teamDoc) {
                final teamData = teamDoc.data();
                final teamBilling =
                    teamData?['billingProfile'] as Map<String, dynamic>?;
                billingProfile = teamBilling != null
                    ? BillingProfile.fromMap(teamBilling)
                    : BillingProfile.empty;
                youdoxConfig = YouDoxConfig.fromMap(
                  teamData?['youdoxConfig'] as Map<String, dynamic>?,
                );
                emit();
              });
        }
        // emit non necessario qui: arriverà dal teamBillingSub
      }, onError: emitError),
    ];

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await _teamBillingSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> seedWorkspace(String userId) async {
    final existing = await _userCollection(userId, 'companies').limit(1).get();
    if (existing.docs.isNotEmpty) {
      return;
    }

    final workspace = buildDemoWorkspace(userId);
    final batch = _firestore.batch();

    for (final company in workspace.companies) {
      batch.set(
        _userCollection(userId, 'companies').doc(company.id),
        company.toMap(),
      );
    }
    for (final project in workspace.projects) {
      batch.set(
        _userCollection(userId, 'projects').doc(project.id),
        project.toMap(),
      );
    }
    for (final phase in workspace.phases) {
      batch.set(_userCollection(userId, 'phases').doc(phase.id), phase.toMap());
    }
    for (final task in workspace.tasks) {
      batch.set(_userCollection(userId, 'tasks').doc(task.id), task.toMap());
    }
    for (final entry in workspace.availability) {
      batch.set(
        _userCollection(userId, 'availability').doc(entry.weekday.toString()),
        entry.toMap(),
      );
    }
    for (final vacation in workspace.vacations) {
      batch.set(
        _userCollection(userId, 'vacations').doc(vacation.id),
        vacation.toMap(),
      );
    }
    for (final slot in workspace.plannedSlots) {
      batch.set(
        _userCollection(userId, 'timelineSlots').doc(slot.id),
        slot.toMap(),
      );
    }
    for (final track in workspace.timeTracks) {
      batch.set(
        _userCollection(userId, 'timeTracks').doc(track.id),
        track.toMap(),
      );
    }
    for (final invoice in workspace.invoiceDrafts) {
      batch.set(
        _userCollection(userId, 'invoices').doc(invoice.id),
        invoice.toMap(),
      );
    }
    for (final contact in workspace.companyContacts) {
      batch.set(
        _userCollection(userId, 'companyContacts').doc(contact.id),
        contact.toMap(),
      );
    }
    for (final ticket in workspace.tickets) {
      batch.set(
        _userCollection(userId, 'tickets').doc(ticket.id),
        ticket.toMap(),
      );
    }
    batch.set(_userDoc(userId), {
      'billingProfile': BillingProfile.empty.toMap(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> updateAvailability(String userId, UserAvailability entry) {
    return _userCollection(
      userId,
      'availability',
    ).doc(entry.weekday.toString()).set(entry.toMap(), SetOptions(merge: true));
  }

  Future<void> createVacation(String userId, VacationPeriod vacation) {
    return _userCollection(
      userId,
      'vacations',
    ).doc(vacation.id).set(vacation.toMap());
  }

  Future<void> deleteVacation(String userId, String vacationId) {
    return _userCollection(userId, 'vacations').doc(vacationId).delete();
  }

  Future<void> createCompany(String userId, Company company) {
    return _userCollection(userId, 'companies').doc(company.id).set({
      ...company.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCompany(String userId, Company company) {
    return _userCollection(userId, 'companies').doc(company.id).set({
      ...company.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> createCompanyContact(String userId, CompanyContact contact) {
    return _userCollection(userId, 'companyContacts').doc(contact.id).set({
      ...contact.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCompanyContact(String userId, CompanyContact contact) {
    return _userCollection(userId, 'companyContacts').doc(contact.id).set({
      ...contact.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteCompanyContact(String userId, String contactId) {
    return _userCollection(userId, 'companyContacts').doc(contactId).delete();
  }

  Future<void> createTicket(String userId, Ticket ticket) {
    return _userCollection(
      userId,
      'tickets',
    ).doc(ticket.id).set(ticket.toMap());
  }

  Future<void> updateTicket(String userId, Ticket ticket) {
    return _userCollection(
      userId,
      'tickets',
    ).doc(ticket.id).set(ticket.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteTicket(String userId, String ticketId) {
    return _userCollection(userId, 'tickets').doc(ticketId).delete();
  }

  Future<void> createProject(String userId, Project project) {
    return _userCollection(userId, 'projects').doc(project.id).set({
      ...project.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setAnticipoEmesso(String userId, String projectId) {
    return _userCollection(userId, 'projects')
        .doc(projectId)
        .set({'anticipoEmesso': true}, SetOptions(merge: true));
  }

  Future<void> updateProject(String userId, Project project) {
    return _userCollection(userId, 'projects').doc(project.id).set({
      ...project.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> createPhase(String userId, ProjectPhase phase) {
    return _userCollection(userId, 'phases').doc(phase.id).set(phase.toMap());
  }

  Future<void> updatePhase(String userId, ProjectPhase phase) {
    return _userCollection(
      userId,
      'phases',
    ).doc(phase.id).set(phase.toMap(), SetOptions(merge: true));
  }

  Future<void> createTask(String userId, WorkTask task) {
    return _userCollection(userId, 'tasks').doc(task.id).set({
      ...task.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateTask(String userId, WorkTask task) {
    return _userCollection(userId, 'tasks').doc(task.id).set({
      ...task.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteTask(String userId, String taskId) {
    return _userCollection(userId, 'tasks').doc(taskId).delete();
  }

  Future<int> deleteBacklogTasks(String userId) async {
    var deleted = 0;
    while (true) {
      final query = await _userCollection(
        userId,
        'tasks',
      ).where('status', isEqualTo: TaskStatus.backlog.name).limit(450).get();
      if (query.docs.isEmpty) {
        break;
      }
      final batch = _firestore.batch();
      for (final doc in query.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += query.docs.length;
    }
    return deleted;
  }

  Future<void> updateTimelineSlot(String userId, TimelineSlot slot) {
    return _userCollection(
      userId,
      'timelineSlots',
    ).doc(slot.id).set(slot.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteTimelineSlot(String userId, String slotId) {
    return _userCollection(userId, 'timelineSlots').doc(slotId).delete();
  }

  Future<void> upsertTimelineSlots(
    String userId,
    List<TimelineSlot> slots,
  ) async {
    if (slots.isEmpty) {
      return;
    }
    final batch = _firestore.batch();
    for (final slot in slots) {
      batch.set(
        _userCollection(userId, 'timelineSlots').doc(slot.id),
        slot.toMap(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> replaceTimelineSlotsForTask(
    String userId, {
    required String taskId,
    required List<TimelineSlot> slots,
  }) async {
    final query = await _userCollection(
      userId,
      'timelineSlots',
    ).where('taskId', isEqualTo: taskId).get();
    final batch = _firestore.batch();
    for (final doc in query.docs) {
      batch.delete(doc.reference);
    }
    for (final slot in slots) {
      batch.set(
        _userCollection(userId, 'timelineSlots').doc(slot.id),
        slot.toMap(),
      );
    }
    await batch.commit();
  }

  Future<void> replaceTimelineSlots(
    String userId,
    List<TimelineSlot> slots,
  ) async {
    final existing = await _userCollection(userId, 'timelineSlots').get();
    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      batch.delete(doc.reference);
    }
    for (final slot in slots) {
      batch.set(
        _userCollection(userId, 'timelineSlots').doc(slot.id),
        slot.toMap(),
      );
    }
    await batch.commit();
  }

  Future<void> removeTimelineSlotsForTask(String userId, String taskId) async {
    final query = await _userCollection(
      userId,
      'timelineSlots',
    ).where('taskId', isEqualTo: taskId).get();
    final batch = _firestore.batch();
    for (final doc in query.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> createTimeTrack(String userId, TimeTrack track) {
    // Aggiungi sempre userId al track per visibilità team
    final trackWithUser = TimeTrack(
      id: track.id,
      taskId: track.taskId,
      name: track.name,
      companyId: track.companyId,
      projectId: track.projectId,
      startAt: track.startAt,
      endAt: track.endAt,
      userId: userId,
      description: track.description,
      billable: track.billable,
    );
    return _userCollection(
      userId,
      'timeTracks',
    ).doc(track.id).set(trackWithUser.toMap());
  }

  Future<void> updateTimeTrack(String userId, TimeTrack track) {
    return _userCollection(
      userId,
      'timeTracks',
    ).doc(track.id).update(track.toMap());
  }

  Future<void> deleteTimeTrack(String userId, String trackId) {
    return _userCollection(userId, 'timeTracks').doc(trackId).delete();
  }

  // ─────────────────────────────────────────────────────────────
  // Task comments
  // ─────────────────────────────────────────────────────────────

  Future<void> createTaskComment(String userId, TaskComment comment) {
    return _userCollection(userId, 'taskComments').doc(comment.id).set({
      ...comment.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<TaskComment>> watchTaskComments(String userId, String taskId) {
    return _userCollection(userId, 'taskComments')
        .where('taskId', isEqualTo: taskId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => TaskComment.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return list;
        });
  }

  Future<void> deleteTaskComment(String userId, String commentId) {
    return _userCollection(userId, 'taskComments').doc(commentId).delete();
  }

  Future<void> updateBillingProfile(
    String userId,
    BillingProfile profile,
  ) async {
    // Se l'utente appartiene a un team, salva il billing sul team (condiviso)
    final userDoc = await _userDoc(userId).get();
    final teamId = userDoc.data()?['teamId'] as String?;
    if (teamId != null) {
      await _firestore.collection('teams').doc(teamId).set({
        'billingProfile': profile.toMap(),
      }, SetOptions(merge: true));
    } else {
      // Fallback: salva sull'utente (legacy)
      await _userDoc(
        userId,
      ).set({'billingProfile': profile.toMap()}, SetOptions(merge: true));
    }
  }

  Future<void> updateYoudoxConfig(String userId, YouDoxConfig config) async {
    final userDoc = await _userDoc(userId).get();
    final teamId = userDoc.data()?['teamId'] as String?;
    if (teamId != null) {
      await _firestore.collection('teams').doc(teamId).set({
        'youdoxConfig': config.toMap(),
      }, SetOptions(merge: true));
    } else {
      await _userDoc(userId).set(
        {'youdoxConfig': config.toMap()},
        SetOptions(merge: true),
      );
    }
  }

  Future<YouDoxConfig> getYoudoxConfig(String userId) async {
    final userDoc = await _userDoc(userId).get();
    final teamId = userDoc.data()?['teamId'] as String?;
    if (teamId != null) {
      final teamDoc = await _firestore.collection('teams').doc(teamId).get();
      return YouDoxConfig.fromMap(
        teamDoc.data()?['youdoxConfig'] as Map<String, dynamic>?,
      );
    }
    return YouDoxConfig.fromMap(
      userDoc.data()?['youdoxConfig'] as Map<String, dynamic>?,
    );
  }

  Future<void> updateEmailSignatureHtml(String userId, String html) {
    return _userDoc(
      userId,
    ).set({'emailSignatureHtml': html}, SetOptions(merge: true));
  }

  Future<void> saveInvoice(
    String userId, {
    required InvoiceDraft invoice,
    Map<String, dynamic> details = const {},
  }) {
    return _userCollection(userId, 'invoices').doc(invoice.id).set({
      ...invoice.toMap(),
      ...details,
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getInvoiceDetails(
    String userId,
    String invoiceId,
  ) async {
    final doc = await _userCollection(userId, 'invoices').doc(invoiceId).get();
    return doc.data();
  }

  Future<void> deleteInvoice(String userId, String invoiceId) {
    return _userCollection(userId, 'invoices').doc(invoiceId).delete();
  }

  Future<Map<String, dynamic>> getUserUiState(String userId) async {
    final doc = await _userDoc(userId).get();
    final data = doc.data();
    final uiState = data?['uiState'];
    if (uiState is Map<String, dynamic>) {
      return uiState;
    }
    if (uiState is Map) {
      return Map<String, dynamic>.from(uiState);
    }
    return const <String, dynamic>{};
  }

  Future<void> saveUserUiState(
    String userId, {
    required int selectedIndex,
    required int todoSub,
    required int finanzeSub,
  }) {
    return _userDoc(userId).set({
      'uiState': {
        'selectedIndex': selectedIndex,
        'todoSub': todoSub,
        'finanzeSub': finanzeSub,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  Future<Map<String, String>> getGoogleCalendarSlotEventMap(
    String userId,
  ) async {
    final snapshot = await _userDoc(
      userId,
    ).collection('googleCalendarSync').get();
    final result = <String, String>{};
    for (final doc in snapshot.docs) {
      final eventId = doc.data()['eventId'] as String?;
      if (eventId != null && eventId.isNotEmpty) {
        result[doc.id] = eventId;
      }
    }
    return result;
  }

  Future<void> setGoogleCalendarSlotEvent(
    String userId, {
    required String slotId,
    required String eventId,
  }) {
    return _userDoc(userId).collection('googleCalendarSync').doc(slotId).set({
      'eventId': eventId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteGoogleCalendarSlotEvent(
    String userId, {
    required String slotId,
  }) {
    return _userDoc(
      userId,
    ).collection('googleCalendarSync').doc(slotId).delete();
  }

  Future<void> upsertPushToken(
    String userId, {
    required String token,
    required String platform,
  }) {
    return _userDoc(userId).collection('pushTokens').doc(token).set({
      'token': token,
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deletePushToken(String userId, {required String token}) {
    return _userDoc(userId).collection('pushTokens').doc(token).delete();
  }

  // ─────────────────────────────────────────────────────────────
  // GUSSONI: Opportunità
  // ─────────────────────────────────────────────────────────────

  Future<String> createOpportunity(String userId, Opportunity opp) async {
    final ref = _userCollection(userId, 'opportunities').doc();
    final withId = Opportunity(
      id: ref.id, companyId: opp.companyId, title: opp.title,
      status: opp.status, createdAt: opp.createdAt,
      createdByUserId: opp.createdByUserId,
      bandoReference: opp.bandoReference, bandoSource: opp.bandoSource,
      bandoDeadline: opp.bandoDeadline, estimatedValue: opp.estimatedValue,
      notes: opp.notes,
    );
    await ref.set(withId.toMap());
    return ref.id;
  }

  Future<void> updateOpportunity(String userId, Opportunity opp) {
    return _userCollection(userId, 'opportunities')
        .doc(opp.id)
        .set(opp.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteOpportunity(String userId, String oppId) {
    return _userCollection(userId, 'opportunities').doc(oppId).delete();
  }

  /// Collega un'azienda a una lista di contatti esistenti e aggiorna
  /// automaticamente le Opportunità che appartengono a quei contatti.
  /// Recupera il termineRendicontazione dall'opportunità collegata, se presente.
  Future<DateTime?> _getTermineRendicontazione(String userId, String opportunityId) async {
    try {
      final doc = await _userCollection(userId, 'opportunities').doc(opportunityId).get();
      if (!doc.exists) return null;
      final raw = doc.data()?['termineRendicontazione'];
      if (raw is Timestamp) return raw.toDate();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> linkCompanyToContacts(
    String userId,
    String companyId,
    List<String> contactIds,
  ) async {
    final batch = _firestore.batch();
    final contactsCol = _userCollection(userId, 'companyContacts');
    final oppsCol = _userCollection(userId, 'opportunities');

    // aggiorna companyId sui contatti
    for (final cId in contactIds) {
      batch.set(contactsCol.doc(cId), {'companyId': companyId}, SetOptions(merge: true));
    }

    // aggiorna le opportunità che hanno contactId in lista ma companyId vuoto
    for (final cId in contactIds) {
      final snap = await oppsCol
          .where('contactId', isEqualTo: cId)
          .where('companyId', isEqualTo: '')
          .get();
      for (final doc in snap.docs) {
        batch.set(oppsCol.doc(doc.id), {'companyId': companyId}, SetOptions(merge: true));
      }
    }

    await batch.commit();
  }

  // ─────────────────────────────────────────────────────────────
  // GUSSONI: Preventivi
  // ─────────────────────────────────────────────────────────────

  Future<String> createGussoniQuotation(String userId, Preventivo q) async {
    final ref = _userCollection(userId, 'gussoniQuotations').doc();
    final withId = Preventivo(
      id: ref.id, opportunityId: q.opportunityId, companyId: q.companyId,
      status: q.status, createdAt: q.createdAt, lines: q.lines,
      istruttoriaFee: q.istruttoriaFee, successFeePercent: q.successFeePercent,
      notes: q.notes,
    );
    await ref.set(withId.toMap());
    // Aggiorna opportunità → quoted
    await _userCollection(userId, 'opportunities').doc(q.opportunityId).update({
      'status': OpportunityStatus.preventivazione.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateGussoniQuotation(String userId, Preventivo q) {
    return _userCollection(userId, 'gussoniQuotations')
        .doc(q.id)
        .set(q.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteGussoniQuotation(String userId, String id) {
    return _userCollection(userId, 'gussoniQuotations').doc(id).delete();
  }

  /// Segna preventivo come accettato + aggiorna opportunità → accepted.
  Future<void> acceptGussoniQuotation(
      String userId, String quotationId, String opportunityId) async {
    final batch = _firestore.batch();
    batch.update(_userCollection(userId, 'gussoniQuotations').doc(quotationId),
        {'status': PreventivoStatus.accepted.name});
    batch.update(_userCollection(userId, 'opportunities').doc(opportunityId),
        {'status': OpportunityStatus.accettata.name,
         'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  // ─────────────────────────────────────────────────────────────
  // GUSSONI: Crea Progetto con configurazione wizard (7 fasi + task)
  // ─────────────────────────────────────────────────────────────

  Future<String> createProjectWithConfig({
    required String userId,
    required String name,
    required String companyId,
    required List<PhaseConfig> phaseConfigs,
    ProjectType type = ProjectType.profit,
    String? opportunityId,
    String? quotationId,
  }) async {
    final now = DateTime.now();
    final batch = _firestore.batch();
    final projectRef = _userCollection(userId, 'projects').doc();

    final project = Project(
      id: projectRef.id,
      companyId: companyId,
      name: name,
      code: 'GUS-${now.year}-${projectRef.id.substring(0, 4).toUpperCase()}',
      status: ProjectStatus.planning.name,
      type: type,
      createdAt: now,
      opportunityId: opportunityId,
      quotationId: quotationId,
    );
    batch.set(projectRef, project.toMap());

    // Crea fasi + task configurati dal wizard
    for (var i = 0; i < phaseConfigs.length; i++) {
      final cfg = phaseConfigs[i];
      final phaseRef = _userCollection(userId, 'phases').doc();
      final phase = ProjectPhase(
        id: phaseRef.id,
        projectId: projectRef.id,
        name: cfg.phaseName,
        order: i,
        status: PhaseStatus.notStarted,
        isCustom: false,
        assignedUserId: cfg.assigneeId,
        startDate: cfg.startDate,
        deadline: cfg.endDate,
      );
      batch.set(phaseRef, phase.toMap());

      // Task della fase — stessa data inizio/fine della fase, stesso assegnatario
      final phaseStart = cfg.startDate ?? now;
      final phaseEnd = cfg.endDate ?? now.add(const Duration(days: 14));

      for (final taskName in cfg.taskNames) {
        final taskRef = _userCollection(userId, 'tasks').doc();
        final task = WorkTask(
          id: taskRef.id,
          companyId: companyId,
          projectId: projectRef.id,
          phaseId: phaseRef.id,
          assigneeId: cfg.assigneeId ?? '',
          name: taskName,
          estimatedHours: 2,
          loggedHours: 0,
          startDate: phaseStart,
          deadline: phaseEnd,
          status: TaskStatus.planned,
          billable: true,
        );
        batch.set(taskRef, {
          ...task.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // Aggiorna preventivo se presente
    if (quotationId != null) {
      batch.update(
        _userCollection(userId, 'gussoniQuotations').doc(quotationId),
        {'linkedProjectId': projectRef.id},
      );
    }

    // Aggiorna opportunità → Presa in carico
    if (opportunityId != null) {
      batch.update(_userCollection(userId, 'opportunities').doc(opportunityId), {
        'status': OpportunityStatus.presaInCarico.name,
        'presaInCarico': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return projectRef.id;
  }

  // ─────────────────────────────────────────────────────────────
  // GUSSONI: Crea Progetto da Preventivo Accettato
  // Crea automaticamente le 4 fasi standard.
  // ─────────────────────────────────────────────────────────────

  Future<String> createProjectFromQuotation({
    required String userId,
    required String name,
    required String companyId,
    required String opportunityId,
    required String quotationId,
    required ProjectType type,
  }) async {
    final batch = _firestore.batch();

    // Progetto
    final projectRef = _userCollection(userId, 'projects').doc();
    final now = DateTime.now();
    final project = Project(
      id: projectRef.id,
      companyId: companyId,
      name: name,
      code: 'GUS-${now.year}-${projectRef.id.substring(0, 4).toUpperCase()}',
      status: ProjectStatus.planning.name,
      type: type,
      createdAt: now,
      opportunityId: opportunityId,
      quotationId: quotationId,
    );
    batch.set(projectRef, project.toMap());

    // 4 fasi standard + task rendicontazione automatici nella fase 3
    String? rendicontazioneFaseId;
    for (var i = 0; i < kDefaultPhaseNames.length; i++) {
      final phaseRef = _userCollection(userId, 'phases').doc();
      final phase = ProjectPhase(
        id: phaseRef.id,
        projectId: projectRef.id,
        name: kDefaultPhaseNames[i],
        order: i,
        status: PhaseStatus.notStarted,
        isCustom: false,
      );
      batch.set(phaseRef, phase.toMap());
      // "Fase 3 – Rendicontazione" → salva l'ID per creare i task automatici
      if (kDefaultPhaseNames[i].contains('Rendicontazione')) {
        rendicontazioneFaseId = phaseRef.id;
      }
    }

    // Task automatici di rendicontazione (Fase 12A/B/C del flusso operativo)
    if (rendicontazioneFaseId != null) {
      // Calcola le date a partire da termineRendicontazione (se disponibile)
      // oppure da today + 30/45/60 giorni
      final termine = opportunityId != null
          ? await _getTermineRendicontazione(userId, opportunityId)
          : null;
      final base = termine ?? now.add(const Duration(days: 60));
      final taskDefs = [
        (
          name: '12A — Raccolta documentale',
          desc: 'Raccogliere i documenti di spesa e pagamento. Verificare la conformità amministrativa e tecnica.',
          deadline: base.subtract(const Duration(days: 28)),
        ),
        (
          name: '12B — Preparazione documentazione',
          desc: 'Predisporre il report di rendicontazione. Compilare i modelli dell\'ente. Verifica finale con il cliente.',
          deadline: base.subtract(const Duration(days: 14)),
        ),
        (
          name: '12C — Invio rendicontazione',
          desc: 'Caricare i documenti sul portale dell\'ente. Inviare la rendicontazione finale.',
          deadline: base,
        ),
      ];

      for (final def in taskDefs) {
        final taskRef = _userCollection(userId, 'tasks').doc();
        final task = WorkTask(
          id: taskRef.id,
          companyId: companyId,
          projectId: projectRef.id,
          phaseId: rendicontazioneFaseId,
          assigneeId: '',
          name: def.name,
          estimatedHours: 2,
          loggedHours: 0,
          startDate: now,
          deadline: def.deadline.isBefore(now) ? now.add(const Duration(days: 7)) : def.deadline,
          status: TaskStatus.planned,
          billable: false,
        );
        batch.set(taskRef, {
          ...task.toMap(),
          'description': def.desc,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // Aggiorna preventivo → linked to project
    batch.update(
      _userCollection(userId, 'gussoniQuotations').doc(quotationId),
      {'linkedProjectId': projectRef.id},
    );

    await batch.commit();
    return projectRef.id;
  }

  // ─────────────────────────────────────────────────────────────
  // GUSSONI: Crea Progetto direttamente da Opportunità
  // (senza preventivo — presa in carico immediata)
  // ─────────────────────────────────────────────────────────────

  Future<String> createProjectFromOpportunity({
    required String userId,
    required String name,
    required String companyId,
    required String opportunityId,
    ProjectType type = ProjectType.profit,
  }) async {
    final now = DateTime.now();
    final batch = _firestore.batch();
    final projectRef = _userCollection(userId, 'projects').doc();

    final project = Project(
      id: projectRef.id,
      companyId: companyId,
      name: name,
      code: 'GUS-${now.year}-${projectRef.id.substring(0, 4).toUpperCase()}',
      status: ProjectStatus.planning.name,
      type: type,
      createdAt: now,
      opportunityId: opportunityId,
    );
    batch.set(projectRef, project.toMap());

    // 4 fasi standard + task rendicontazione
    String? rendicontazioneFaseId;
    for (var i = 0; i < kDefaultPhaseNames.length; i++) {
      final phaseRef = _userCollection(userId, 'phases').doc();
      final phase = ProjectPhase(
        id: phaseRef.id,
        projectId: projectRef.id,
        name: kDefaultPhaseNames[i],
        order: i,
        status: PhaseStatus.notStarted,
        isCustom: false,
      );
      batch.set(phaseRef, phase.toMap());
      if (kDefaultPhaseNames[i].contains('Rendicontazione')) {
        rendicontazioneFaseId = phaseRef.id;
      }
    }

    // Task rendicontazione automatici
    if (rendicontazioneFaseId != null) {
      final termine = await _getTermineRendicontazione(userId, opportunityId);
      final base = termine ?? now.add(const Duration(days: 60));
      final taskDefs = [
        (name: '12A — Raccolta documentale',
         desc: 'Raccogliere i documenti di spesa e pagamento. Verificare la conformità.',
         deadline: base.subtract(const Duration(days: 28))),
        (name: '12B — Preparazione documentazione',
         desc: 'Predisporre il report di rendicontazione. Compilare i modelli dell\'ente.',
         deadline: base.subtract(const Duration(days: 14))),
        (name: '12C — Invio rendicontazione',
         desc: 'Caricare i documenti sul portale. Inviare la rendicontazione finale.',
         deadline: base),
      ];
      for (final def in taskDefs) {
        final taskRef = _userCollection(userId, 'tasks').doc();
        final task = WorkTask(
          id: taskRef.id, companyId: companyId,
          projectId: projectRef.id, phaseId: rendicontazioneFaseId,
          assigneeId: '', name: def.name,
          estimatedHours: 2, loggedHours: 0,
          startDate: now,
          deadline: def.deadline.isBefore(now) ? now.add(const Duration(days: 7)) : def.deadline,
          status: TaskStatus.planned, billable: false,
        );
        batch.set(taskRef, {...task.toMap(), 'description': def.desc, 'createdAt': FieldValue.serverTimestamp()});
      }
    }

    // Aggiorna opportunità → Presa in carico
    batch.update(_userCollection(userId, 'opportunities').doc(opportunityId), {
      'status': OpportunityStatus.presaInCarico.name,
      'presaInCarico': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return projectRef.id;
  }

  // ─────────────────────────────────────────────────────────────
  // GUSSONI: Assegna fase a un utente
  // ─────────────────────────────────────────────────────────────

  Future<void> assignPhase(
      String userId, String phaseId, String? assignedUserId,
      {DateTime? deadline}) {
    return _userCollection(userId, 'phases').doc(phaseId).update({
      'assignedUserId': assignedUserId,
      if (deadline != null) 'deadline': Timestamp.fromDate(deadline),
    });
  }

  Future<void> updatePhaseStatus(
      String userId, String phaseId, PhaseStatus status) {
    return _userCollection(userId, 'phases')
        .doc(phaseId)
        .update({'status': status.name});
  }

  // ─────────────────────────────────────────────────────────────
  // GUSSONI: Chiusura progetto → auto-genera fattura bozza
  // ─────────────────────────────────────────────────────────────

  Future<void> closeProjectWithInvoice({
    required String userId,
    required Project project,
    required double grantAmount,
  }) async {
    final batch = _firestore.batch();
    final quotation = null; // verrà passato come parametro se necessario

    // Calcola success fee
    final successFee = grantAmount <= 50000
        ? grantAmount * 0.09
        : grantAmount * 0.08;

    // Aggiorna progetto
    batch.update(_userCollection(userId, 'projects').doc(project.id), {
      'status': ProjectStatus.approved.name,
      'grantAmount': grantAmount,
      'successFeeAmount': successFee,
      'closedAt': FieldValue.serverTimestamp(),
    });

    // Crea fattura bozza per success fee
    final invoiceRef = _userCollection(userId, 'invoices').doc();
    final now = DateTime.now();
    final invoiceNumber =
        'SF-${now.year}-${invoiceRef.id.substring(0, 6).toUpperCase()}';
    final invoice = InvoiceDraft(
      id: invoiceRef.id,
      companyId: project.companyId,
      number: invoiceNumber,
      amount: successFee,
      status: InvoiceStatus.draft,
      projectId: project.id,
      isSuccessFee: true,
      grantAmount: grantAmount,
      lines: [
        InvoiceLine(
          description:
              'Success fee – Contributo ottenuto: €${grantAmount.toStringAsFixed(2)} – ${project.name}',
          quantity: 1,
          unitPrice: successFee,
          vatPercent: 22,
        ),
      ],
      notes: 'Fattura di premialità generata automaticamente alla chiusura del progetto.',
      createdAt: now,
    );
    batch.set(invoiceRef, invoice.toMap());

    await batch.commit();
  }

  /// Aggiunge una fase custom a un progetto esistente.
  Future<void> addCustomPhase(String userId,
      {required String projectId, required String name, required int order}) {
    final ref = _userCollection(userId, 'phases').doc();
    return ref.set(ProjectPhase(
      id: ref.id,
      projectId: projectId,
      name: name,
      order: order,
      status: PhaseStatus.notStarted,
      isCustom: true,
    ).toMap());
  }
}
