import '../../brand_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/crm_models.dart';

// ────────────────────────────────────────────────
// CrmStore – ChangeNotifier with full mock CRM state
// ────────────────────────────────────────────────

class CrmStore extends ChangeNotifier {
  CrmStore({
    required this.currentTeam,
    required this.currentUser,
    required List<CrmTeam> teams,
    required List<CrmTeamMember> members,
    required List<CrmUser> users,
    required List<CrmCompany> companies,
    required List<CrmContact> contacts,
    required List<CrmPipelineStage> pipelineStages,
    required List<CrmDeal> deals,
    required List<CrmTask> tasks,
    required List<CrmComment> comments,
    required List<CrmNote> notes,
    required List<CrmProject> projects,
    required List<CrmMilestone> milestones,
    required List<CrmQuotation> quotations,
    required List<CrmInvoice> invoices,
    required List<CrmActivityItem> activityItems,
  })  : _teams = teams,
        _members = members,
        _users = users,
        _companies = companies,
        _contacts = contacts,
        _pipelineStages = pipelineStages,
        _deals = deals,
        _tasks = tasks,
        _comments = comments,
        _notes = notes,
        _projects = projects,
        _milestones = milestones,
        _quotations = quotations,
        _invoices = invoices,
        _activityItems = activityItems;

  CrmTeam currentTeam;
  CrmUser currentUser;

  List<CrmTeam> _teams;
  List<CrmTeamMember> _members;
  List<CrmUser> _users;
  List<CrmCompany> _companies;
  List<CrmContact> _contacts;
  List<CrmPipelineStage> _pipelineStages;
  List<CrmDeal> _deals;
  List<CrmTask> _tasks;
  List<CrmComment> _comments;
  List<CrmNote> _notes;
  List<CrmProject> _projects;
  List<CrmMilestone> _milestones;
  List<CrmQuotation> _quotations;
  List<CrmInvoice> _invoices;
  List<CrmActivityItem> _activityItems;

  // Getters for current team
  String get teamId => currentTeam.id;

  List<CrmTeam> get teams => _teams;
  List<CrmTeamMember> get members => _members.where((m) => m.teamId == teamId).toList();
  List<CrmUser> get users => _users;
  List<CrmCompany> get companies => _companies.where((c) => c.teamId == teamId).toList()..sort((a, b) => a.name.compareTo(b.name));
  List<CrmContact> get contacts => _contacts.where((c) => c.teamId == teamId).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));
  List<CrmPipelineStage> get pipelineStages => _pipelineStages.where((s) => s.teamId == teamId).toList()..sort((a, b) => a.order.compareTo(b.order));
  List<CrmDeal> get deals => _deals.where((d) => d.teamId == teamId).toList()..sort((a, b) => (b.updatedAt ?? DateTime.now()).compareTo(a.updatedAt ?? DateTime.now()));
  List<CrmTask> get tasks => _tasks.where((t) => t.teamId == teamId).toList()..sort((a, b) => (a.dueDate ?? DateTime(2099)).compareTo(b.dueDate ?? DateTime(2099)));
  List<CrmComment> get comments => _comments.where((c) => c.teamId == teamId).toList();
  List<CrmNote> get notes => _notes.where((n) => n.teamId == teamId).toList();
  List<CrmProject> get projects => _projects.where((p) => p.teamId == teamId).toList()..sort((a, b) => a.title.compareTo(b.title));
  List<CrmMilestone> get milestones => _milestones.where((m) => m.teamId == teamId).toList();
  List<CrmQuotation> get quotations => _quotations.where((q) => q.teamId == teamId).toList()..sort((a, b) => b.number.compareTo(a.number));
  List<CrmInvoice> get invoices => _invoices.where((i) => i.teamId == teamId).toList()..sort((a, b) => b.number.compareTo(a.number));
  List<CrmActivityItem> get activityItems {
    final items = _activityItems.where((a) => a.teamId == teamId).toList();
    items.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
    return items;
  }

  // Helpers
  CrmUser? userById(String? id) => id == null ? null : _users.firstWhere((u) => u.id == id, orElse: () => _users.first);
  CrmCompany? companyById(String? id) => id == null ? null : _companies.where((c) => c.id == id).firstOrNull;
  CrmContact? contactById(String? id) => id == null ? null : _contacts.where((c) => c.id == id).firstOrNull;
  CrmPipelineStage? stageById(String? id) => id == null ? null : _pipelineStages.where((s) => s.id == id).firstOrNull;

  List<CrmDeal> dealsForCompany(String companyId) => deals.where((d) => d.customerId == companyId).toList();
  List<CrmTask> tasksForUser(String userId) => tasks.where((t) => t.assignedTo == userId).toList();
  List<CrmTask> tasksForEntity(String entityType, String entityId) =>
      tasks.where((t) => t.relatedEntityType == entityType && t.relatedEntityId == entityId).toList();
  List<CrmDeal> dealsInStage(String stageId) => deals.where((d) => d.stageId == stageId && d.status == DealStatus.open).toList();

  // Stats
  double get totalOpenDealValue => deals.where((d) => d.status == DealStatus.open).fold(0, (sum, d) => sum + d.value);
  int get openTaskCount => tasks.where((t) => t.status != CrmTaskStatus.done && t.status != CrmTaskStatus.cancelled).length;
  int get overdueTaskCount => tasks.where((t) => t.isOverdue).length;
  int get activeProjectCount => projects.where((p) => p.status == CrmProjectStatus.running).length;

  // ────── Deal CRUD ──────

  void addDeal(CrmDeal deal) {
    _deals = [..._deals, deal];
    _addActivity(CrmActivityItem(
      id: 'act-${DateTime.now().microsecondsSinceEpoch}',
      teamId: teamId,
      entityType: 'deal',
      entityId: deal.id,
      actorId: currentUser.id,
      actionType: CrmActivityActionType.created,
      title: 'Deal creato: ${deal.title}',
      createdAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void updateDeal(CrmDeal deal) {
    _deals = _deals.map((d) => d.id == deal.id ? deal : d).toList();
    notifyListeners();
  }

  void moveDeal(String dealId, String newStageId) {
    final deal = _deals.firstWhere((d) => d.id == dealId);
    final oldStage = stageById(deal.stageId);
    final newStage = stageById(newStageId);
    _deals = _deals.map((d) => d.id == dealId ? d.copyWith(stageId: newStageId) : d).toList();
    _addActivity(CrmActivityItem(
      id: 'act-${DateTime.now().microsecondsSinceEpoch}',
      teamId: teamId,
      entityType: 'deal',
      entityId: dealId,
      actorId: currentUser.id,
      actionType: CrmActivityActionType.dealMoved,
      title: '${deal.title} spostato: ${oldStage?.name ?? '?'} → ${newStage?.name ?? '?'}',
      createdAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void closeDeal(String dealId, DealStatus result) {
    _deals = _deals.map((d) => d.id == dealId ? d.copyWith(status: result) : d).toList();
    notifyListeners();
  }

  void deleteDeal(String id) {
    _deals = _deals.where((d) => d.id != id).toList();
    notifyListeners();
  }

  // ────── Task CRUD ──────

  void addTask(CrmTask task) {
    _tasks = [..._tasks, task];
    notifyListeners();
  }

  void updateTask(CrmTask task) {
    _tasks = _tasks.map((t) => t.id == task.id ? task : t).toList();
    if (task.status == CrmTaskStatus.done) {
      _addActivity(CrmActivityItem(
        id: 'act-${DateTime.now().microsecondsSinceEpoch}',
        teamId: teamId,
        entityType: 'task',
        entityId: task.id,
        actorId: currentUser.id,
        actionType: CrmActivityActionType.taskCompleted,
        title: 'Task completato: ${task.title}',
        createdAt: DateTime.now(),
      ));
    }
    notifyListeners();
  }

  void deleteTask(String id) {
    _tasks = _tasks.where((t) => t.id != id).toList();
    notifyListeners();
  }

  // ────── Company CRUD ──────

  void addCompany(CrmCompany company) {
    _companies = [..._companies, company];
    notifyListeners();
  }

  void updateCompany(CrmCompany company) {
    _companies = _companies.map((c) => c.id == company.id ? company : c).toList();
    notifyListeners();
  }

  // ────── Contact CRUD ──────

  void addContact(CrmContact contact) {
    _contacts = [..._contacts, contact];
    notifyListeners();
  }

  void updateContact(CrmContact contact) {
    _contacts = _contacts.map((c) => c.id == contact.id ? contact : c).toList();
    notifyListeners();
  }

  // ────── Internal ──────

  void _addActivity(CrmActivityItem item) {
    _activityItems = [item, ..._activityItems];
  }

  // ────────────────────────────────────────────────
  // Factory: build realistic mock for a web agency
  // ────────────────────────────────────────────────

  static CrmStore buildMock() {
    const teamId = 'team-gweb';
    final now = DateTime.now();

    // Users
    final users = [
      CrmUser(id: 'u-owner', firstName: 'Matteo', lastName: 'Broggini', email: 'matteo@gweb.it', phone: '+39 339 1234567', createdAt: now.subtract(const Duration(days: 365))),
      CrmUser(id: 'u-admin', firstName: 'Riccardo', lastName: 'Sacchetto', email: 'riccardo@gweb.it', phone: '+39 347 9876543', createdAt: now.subtract(const Duration(days: 300))),
      CrmUser(id: 'u-mgr', firstName: 'Sara', lastName: 'Colombo', email: 'sara@gweb.it', phone: '+39 331 5551234', createdAt: now.subtract(const Duration(days: 200))),
      CrmUser(id: 'u-dev', firstName: 'Marco', lastName: 'Bianchi', email: 'marco@gweb.it', phone: '+39 345 7891234', createdAt: now.subtract(const Duration(days: 90))),
    ];

    // Team
    final team = CrmTeam(
      id: teamId,
      name: 'Gweb Digital',
      ownerId: 'u-owner',
      members: users.map((u) => u.id).toList(),
      createdAt: now.subtract(const Duration(days: 400)),
    );

    // Team members
    final members = [
      const CrmTeamMember(id: 'tm-1', userId: 'u-owner', teamId: teamId, role: TeamMemberRole.owner, status: TeamMemberStatus.active),
      const CrmTeamMember(id: 'tm-2', userId: 'u-admin', teamId: teamId, role: TeamMemberRole.admin, status: TeamMemberStatus.active),
      const CrmTeamMember(id: 'tm-3', userId: 'u-mgr', teamId: teamId, role: TeamMemberRole.manager, status: TeamMemberStatus.active),
      const CrmTeamMember(id: 'tm-4', userId: 'u-dev', teamId: teamId, role: TeamMemberRole.member, status: TeamMemberStatus.active),
    ];

    // Companies
    final companies = [
      CrmCompany(id: 'cmp-1', teamId: teamId, name: 'Innovatech Srl', email: 'info@innovatech.it', phone: '02 9876543', website: 'www.innovatech.it', address: 'Via Brera 12, Milano', vatNumber: 'IT04532810965', tags: const ['enterprise', 'tech'], assignedTo: 'u-admin', createdBy: 'u-owner', createdAt: now.subtract(const Duration(days: 200))),
      CrmCompany(id: 'cmp-2', teamId: teamId, name: 'Studio Legale Rossi', email: 'rossi@studiolegale.it', phone: '011 4567890', website: 'www.studiorossi.it', address: 'Corso Re Umberto 45, Torino', vatNumber: 'IT09871234567', tags: const ['legal', 'pmi'], assignedTo: 'u-mgr', createdBy: 'u-owner', createdAt: now.subtract(const Duration(days: 180))),
      CrmCompany(id: 'cmp-3', teamId: teamId, name: 'Ferramenta Morelli', email: 'info@morelli.com', phone: '055 3219876', website: 'www.morelli.com', address: 'Via Nazionale 78, Firenze', vatNumber: 'IT07654321098', tags: const ['retail', 'pmi'], assignedTo: 'u-dev', createdBy: 'u-admin', createdAt: now.subtract(const Duration(days: 150))),
      CrmCompany(id: 'cmp-4', teamId: teamId, name: 'MedGroup SpA', email: 'ufficio@medgroup.it', phone: '06 56781234', website: 'www.medgroup.it', address: 'Viale Parioli 22, Roma', vatNumber: 'IT05432198765', tags: const ['healthcare', 'enterprise'], assignedTo: 'u-admin', createdBy: 'u-owner', createdAt: now.subtract(const Duration(days: 120))),
      CrmCompany(id: 'cmp-5', teamId: teamId, name: 'Edilgreen Srl', email: 'info@edilgreen.it', phone: '051 8902345', website: 'www.edilgreen.it', address: 'Via Emilia Ovest 234, Bologna', vatNumber: 'IT08123456789', tags: const ['costruzioni', 'sostenibilita'], assignedTo: 'u-mgr', createdBy: 'u-admin', createdAt: now.subtract(const Duration(days: 60))),
    ];

    // Contacts
    final contacts = [
      CrmContact(id: 'cnt-1', teamId: teamId, firstName: 'Luca', lastName: 'Rossi', companyId: 'cmp-1', email: 'l.rossi@innovatech.it', phone: '+39 335 1112233', role: 'CTO', assignedTo: 'u-admin', createdBy: 'u-owner', createdAt: now.subtract(const Duration(days: 195))),
      CrmContact(id: 'cnt-2', teamId: teamId, firstName: 'Giulia', lastName: 'Ferrari', companyId: 'cmp-1', email: 'g.ferrari@innovatech.it', phone: '+39 347 4445566', role: 'Responsabile Marketing', assignedTo: 'u-mgr', createdBy: 'u-admin', createdAt: now.subtract(const Duration(days: 185))),
      CrmContact(id: 'cnt-3', teamId: teamId, firstName: 'Avv. Andrea', lastName: 'Rossi', companyId: 'cmp-2', email: 'a.rossi@studiolegale.it', phone: '+39 339 7778899', role: 'Titolare', assignedTo: 'u-mgr', createdBy: 'u-owner', createdAt: now.subtract(const Duration(days: 175))),
      CrmContact(id: 'cnt-4', teamId: teamId, firstName: 'Paolo', lastName: 'Morelli', companyId: 'cmp-3', email: 'p.morelli@morelli.com', phone: '+39 340 0001112', role: 'Proprietario', assignedTo: 'u-dev', createdBy: 'u-admin', createdAt: now.subtract(const Duration(days: 145))),
      CrmContact(id: 'cnt-5', teamId: teamId, firstName: 'Dott.ssa Elena', lastName: 'Marinelli', companyId: 'cmp-4', email: 'e.marinelli@medgroup.it', phone: '+39 338 2223334', role: 'Direttore Generale', assignedTo: 'u-admin', createdBy: 'u-owner', createdAt: now.subtract(const Duration(days: 115))),
      CrmContact(id: 'cnt-6', teamId: teamId, firstName: 'Roberto', lastName: 'Verdi', companyId: 'cmp-5', email: 'r.verdi@edilgreen.it', phone: '+39 344 5556667', role: 'CEO', assignedTo: 'u-mgr', createdBy: 'u-admin', createdAt: now.subtract(const Duration(days: 55))),
      CrmContact(id: 'cnt-7', teamId: teamId, firstName: 'Chiara', lastName: 'Esposito', companyId: null, email: 'chiara.esposito@gmail.com', phone: '+39 320 9990011', role: 'Freelance Designer', assignedTo: 'u-dev', createdBy: 'u-mgr', createdAt: now.subtract(const Duration(days: 30))),
    ];

    // Pipeline stages
    final stages = [
      CrmPipelineStage(id: 'stage-1', teamId: teamId, name: 'Lead', order: 1, color: const Color(0xFF7D89A8), probability: 10),
      CrmPipelineStage(id: 'stage-2', teamId: teamId, name: 'Qualificazione', order: 2, color: const Color(0xFF0369A1), probability: 30),
      CrmPipelineStage(id: 'stage-3', teamId: teamId, name: 'Proposta', order: 3, color: GussoniBrand.primary, probability: 60),
      CrmPipelineStage(id: 'stage-4', teamId: teamId, name: 'Trattativa', order: 4, color: const Color(0xFFD97706), probability: 80),
      CrmPipelineStage(id: 'stage-5', teamId: teamId, name: 'Chiuso', order: 5, color: GussoniBrand.primary, probability: 100),
    ];

    // Deals
    final deals = [
      CrmDeal(id: 'deal-1', teamId: teamId, title: 'Sito web istituzionale', stageId: 'stage-1', status: DealStatus.open, value: 3500, customerId: 'cmp-3', customerType: 'company', probability: 15, expectedClosingDate: now.add(const Duration(days: 45)), assignedTo: 'u-dev', createdBy: 'u-admin', notes: 'Cliente interessato a restyling completo', createdAt: now.subtract(const Duration(days: 20)), updatedAt: now.subtract(const Duration(days: 5))),
      CrmDeal(id: 'deal-2', teamId: teamId, title: 'CRM aziendale personalizzato', stageId: 'stage-2', status: DealStatus.open, value: 12000, customerId: 'cmp-1', customerType: 'company', probability: 35, expectedClosingDate: now.add(const Duration(days: 30)), assignedTo: 'u-admin', createdBy: 'u-owner', notes: 'Richiesta integrazione con sistema legacy', createdAt: now.subtract(const Duration(days: 35)), updatedAt: now.subtract(const Duration(days: 3))),
      CrmDeal(id: 'deal-3', teamId: teamId, title: 'App mobile prenotazioni', stageId: 'stage-3', status: DealStatus.open, value: 18500, customerId: 'cmp-4', customerType: 'company', probability: 65, expectedClosingDate: now.add(const Duration(days: 15)), assignedTo: 'u-admin', createdBy: 'u-owner', notes: 'Demo approvata, in attesa del legale', createdAt: now.subtract(const Duration(days: 50)), updatedAt: now.subtract(const Duration(days: 1))),
      CrmDeal(id: 'deal-4', teamId: teamId, title: 'Portale clienti Studio Rossi', stageId: 'stage-4', status: DealStatus.open, value: 7200, customerId: 'cmp-2', customerType: 'company', probability: 82, expectedClosingDate: now.add(const Duration(days: 7)), assignedTo: 'u-mgr', createdBy: 'u-owner', notes: 'Contratto quasi pronto', createdAt: now.subtract(const Duration(days: 60)), updatedAt: now.subtract(const Duration(hours: 8))),
      CrmDeal(id: 'deal-5', teamId: teamId, title: 'E-commerce materiali edili', stageId: 'stage-2', status: DealStatus.open, value: 9800, customerId: 'cmp-5', customerType: 'company', probability: 30, expectedClosingDate: now.add(const Duration(days: 60)), assignedTo: 'u-mgr', createdBy: 'u-admin', notes: 'Primo contatto promettente', createdAt: now.subtract(const Duration(days: 10)), updatedAt: now.subtract(const Duration(days: 2))),
      CrmDeal(id: 'deal-6', teamId: teamId, title: 'Newsletter automation', stageId: 'stage-5', status: DealStatus.won, value: 2400, customerId: 'cmp-1', customerType: 'company', probability: 100, expectedClosingDate: now.subtract(const Duration(days: 5)), assignedTo: 'u-admin', createdBy: 'u-owner', createdAt: now.subtract(const Duration(days: 90)), updatedAt: now.subtract(const Duration(days: 5))),
    ];

    // Tasks
    final tasks = [
      CrmTask(id: 'ctask-1', teamId: teamId, title: 'Preparare proposta commerciale MedGroup', status: CrmTaskStatus.inProgress, priority: CrmTaskPriority.high, description: 'Includere specifiche tecniche e mockup dell\'app', assignedTo: 'u-admin', createdBy: 'u-owner', relatedEntityType: 'deal', relatedEntityId: 'deal-3', dueDate: now.add(const Duration(days: 2)), createdAt: now.subtract(const Duration(days: 3))),
      CrmTask(id: 'ctask-2', teamId: teamId, title: 'Call di follow-up con Studio Rossi', status: CrmTaskStatus.open, priority: CrmTaskPriority.urgent, description: 'Verificare stato approvazione contratto', assignedTo: 'u-mgr', createdBy: 'u-owner', relatedEntityType: 'deal', relatedEntityId: 'deal-4', dueDate: now.add(const Duration(days: 1)), createdAt: now.subtract(const Duration(days: 1))),
      CrmTask(id: 'ctask-3', teamId: teamId, title: 'Onboarding cliente Edilgreen', status: CrmTaskStatus.open, priority: CrmTaskPriority.medium, description: 'Raccogliere materiali e credenziali accesso', assignedTo: 'u-dev', createdBy: 'u-mgr', relatedEntityType: 'company', relatedEntityId: 'cmp-5', dueDate: now.add(const Duration(days: 5)), createdAt: now.subtract(const Duration(days: 2))),
      CrmTask(id: 'ctask-4', teamId: teamId, title: 'Aggiornare wireframe sito Morelli', status: CrmTaskStatus.waiting, priority: CrmTaskPriority.medium, description: 'In attesa feedback cliente su palette colori', assignedTo: 'u-dev', createdBy: 'u-admin', relatedEntityType: 'deal', relatedEntityId: 'deal-1', dueDate: now.add(const Duration(days: 8)), createdAt: now.subtract(const Duration(days: 4))),
      CrmTask(id: 'ctask-5', teamId: teamId, title: 'Inviare fattura Innovatech newsletter', status: CrmTaskStatus.done, priority: CrmTaskPriority.high, description: '', assignedTo: 'u-admin', createdBy: 'u-owner', relatedEntityType: 'deal', relatedEntityId: 'deal-6', dueDate: now.subtract(const Duration(days: 5)), completedAt: now.subtract(const Duration(days: 5)), createdAt: now.subtract(const Duration(days: 10))),
      CrmTask(id: 'ctask-6', teamId: teamId, title: 'Analisi requisiti CRM Innovatech', status: CrmTaskStatus.inProgress, priority: CrmTaskPriority.high, description: 'Intervistare i responsabili di reparto', assignedTo: 'u-admin', createdBy: 'u-owner', relatedEntityType: 'deal', relatedEntityId: 'deal-2', dueDate: now.add(const Duration(days: 4)), createdAt: now.subtract(const Duration(days: 5))),
      CrmTask(id: 'ctask-7', teamId: teamId, title: 'Review privacy policy e GDPR', status: CrmTaskStatus.open, priority: CrmTaskPriority.low, description: '', assignedTo: 'u-mgr', createdBy: 'u-owner', dueDate: now.add(const Duration(days: 14)), createdAt: now.subtract(const Duration(days: 7))),
    ];

    // Projects
    final projects = [
      CrmProject(id: 'proj-1', teamId: teamId, title: 'App Prenotazioni MedGroup', status: CrmProjectStatus.running, ownerId: 'u-admin', description: 'App mobile iOS/Android per prenotazioni visite mediche', customerId: 'cmp-4', customerType: 'company', members: const ['u-admin', 'u-dev'], startDate: now.subtract(const Duration(days: 30)), endDate: now.add(const Duration(days: 60)), budget: 18500, createdAt: now.subtract(const Duration(days: 30))),
      CrmProject(id: 'proj-2', teamId: teamId, title: 'Portale Web Studio Rossi', status: CrmProjectStatus.running, ownerId: 'u-mgr', description: 'Area clienti con gestione pratiche e documenti', customerId: 'cmp-2', customerType: 'company', members: const ['u-mgr', 'u-dev'], startDate: now.subtract(const Duration(days: 15)), endDate: now.add(const Duration(days: 30)), budget: 7200, createdAt: now.subtract(const Duration(days: 15))),
      CrmProject(id: 'proj-3', teamId: teamId, title: 'Newsletter Automation Innovatech', status: CrmProjectStatus.closed, ownerId: 'u-admin', description: 'Integrazione MailChimp e automazioni marketing', customerId: 'cmp-1', customerType: 'company', members: const ['u-admin'], startDate: now.subtract(const Duration(days: 60)), endDate: now.subtract(const Duration(days: 5)), budget: 2400, createdAt: now.subtract(const Duration(days: 60))),
    ];

    // Milestones
    final milestones = [
      CrmMilestone(id: 'ms-1', teamId: teamId, projectId: 'proj-1', title: 'Consegna wireframe', status: 'done', responsibleUserId: 'u-admin', dueDate: now.subtract(const Duration(days: 10))),
      CrmMilestone(id: 'ms-2', teamId: teamId, projectId: 'proj-1', title: 'Review backend API', status: 'running', responsibleUserId: 'u-dev', dueDate: now.add(const Duration(days: 14))),
      CrmMilestone(id: 'ms-3', teamId: teamId, projectId: 'proj-2', title: 'Progettazione DB', status: 'done', responsibleUserId: 'u-dev', dueDate: now.subtract(const Duration(days: 5))),
    ];

    // Quotations
    final quotations = [
      CrmQuotation(id: 'quot-1', teamId: teamId, number: 'PRV-2025-001', status: CrmQuotationStatus.sent, customerId: 'cmp-3', customerType: 'company', lines: const [CrmLineItem(description: 'Sito web istituzionale – design + sviluppo', quantity: 1, unitPrice: 3500), CrmLineItem(description: 'Hosting e dominio annuale', quantity: 1, unitPrice: 120)], createdAt: DateTime(2025, 3, 15)),
      CrmQuotation(id: 'quot-2', teamId: teamId, number: 'PRV-2025-002', status: CrmQuotationStatus.accepted, customerId: 'cmp-5', customerType: 'company', lines: const [CrmLineItem(description: 'E-commerce – setup e configurazione', quantity: 1, unitPrice: 6500), CrmLineItem(description: 'Integrazione gateway pagamento', quantity: 1, unitPrice: 800), CrmLineItem(description: 'Formazione team', quantity: 4, unitPrice: 125)], createdAt: DateTime(2025, 4, 1)),
    ];

    // Invoices
    final invoices = [
      CrmInvoice(id: 'inv-1', teamId: teamId, number: 'FT-2025-001', status: CrmInvoiceStatus.paid, customerId: 'cmp-1', customerType: 'company', lines: const [CrmLineItem(description: 'Newsletter automation – setup', quantity: 1, unitPrice: 2400)], dueDate: DateTime(2025, 3, 31), createdAt: DateTime(2025, 3, 1)),
      CrmInvoice(id: 'inv-2', teamId: teamId, number: 'FT-2025-002', status: CrmInvoiceStatus.sent, customerId: 'cmp-4', customerType: 'company', lines: const [CrmLineItem(description: 'App prenotazioni – acconto 30%', quantity: 1, unitPrice: 5550)], dueDate: now.add(const Duration(days: 15)), createdAt: now.subtract(const Duration(days: 7))),
      CrmInvoice(id: 'inv-3', teamId: teamId, number: 'FT-2025-003', status: CrmInvoiceStatus.overdue, customerId: 'cmp-2', customerType: 'company', lines: const [CrmLineItem(description: 'Consulenza sviluppo portale – ore 12', quantity: 12, unitPrice: 95)], dueDate: now.subtract(const Duration(days: 10)), createdAt: now.subtract(const Duration(days: 40))),
    ];

    // Activity items
    final activity = [
      CrmActivityItem(id: 'act-1', teamId: teamId, entityType: 'deal', entityId: 'deal-4', actorId: 'u-mgr', actionType: CrmActivityActionType.dealMoved, title: 'Deal spostato in Trattativa: Portale Studio Rossi', createdAt: now.subtract(const Duration(hours: 8))),
      CrmActivityItem(id: 'act-2', teamId: teamId, entityType: 'task', entityId: 'ctask-5', actorId: 'u-admin', actionType: CrmActivityActionType.taskCompleted, title: 'Task completato: Inviare fattura Innovatech', createdAt: now.subtract(const Duration(days: 5, hours: 2))),
      CrmActivityItem(id: 'act-3', teamId: teamId, entityType: 'deal', entityId: 'deal-6', actorId: 'u-owner', actionType: CrmActivityActionType.statusChanged, title: 'Deal vinto: Newsletter automation Innovatech (€ 2.400)', createdAt: now.subtract(const Duration(days: 5, hours: 4))),
      CrmActivityItem(id: 'act-4', teamId: teamId, entityType: 'company', entityId: 'cmp-5', actorId: 'u-admin', actionType: CrmActivityActionType.created, title: 'Nuova azienda aggiunta: Edilgreen Srl', createdAt: now.subtract(const Duration(days: 10))),
      CrmActivityItem(id: 'act-5', teamId: teamId, entityType: 'deal', entityId: 'deal-3', actorId: 'u-admin', actionType: CrmActivityActionType.commented, title: 'Commento su App prenotazioni MedGroup', description: 'Demo presentata ai referenti clinici. Feedback molto positivo.', createdAt: now.subtract(const Duration(days: 2))),
      CrmActivityItem(id: 'act-6', teamId: teamId, entityType: 'task', entityId: 'ctask-1', actorId: 'u-admin', actionType: CrmActivityActionType.taskCreated, title: 'Nuovo task: Preparare proposta commerciale MedGroup', createdAt: now.subtract(const Duration(days: 3))),
      CrmActivityItem(id: 'act-7', teamId: teamId, entityType: 'deal', entityId: 'deal-5', actorId: 'u-mgr', actionType: CrmActivityActionType.created, title: 'Nuovo deal: E-commerce materiali edili (Edilgreen)', createdAt: now.subtract(const Duration(days: 10))),
    ];

    return CrmStore(
      currentTeam: team,
      currentUser: users[1], // Riccardo
      teams: [team],
      members: members,
      users: users,
      companies: companies,
      contacts: contacts,
      pipelineStages: stages,
      deals: deals,
      tasks: tasks,
      comments: const [],
      notes: const [],
      projects: projects,
      milestones: milestones,
      quotations: quotations,
      invoices: invoices,
      activityItems: activity,
    );
  }
}
