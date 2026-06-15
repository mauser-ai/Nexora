import '../models/domain_models.dart';
import '../services/planning_service.dart';

class DemoWorkspace {
  DemoWorkspace({
    required this.companies,
    required this.companyContacts,
    required this.tickets,
    required this.projects,
    required this.phases,
    required this.tasks,
    required this.availability,
    required this.vacations,
    required this.plannedSlots,
    required this.timeTracks,
    required this.invoiceDrafts,
  });

  final List<Company> companies;
  final List<CompanyContact> companyContacts;
  final List<Ticket> tickets;
  final List<Project> projects;
  final List<ProjectPhase> phases;
  final List<WorkTask> tasks;
  final List<UserAvailability> availability;
  final List<VacationPeriod> vacations;
  final List<TimelineSlot> plannedSlots;
  final List<TimeTrack> timeTracks;
  final List<InvoiceDraft> invoiceDrafts;
}

DemoWorkspace buildDemoWorkspace(String userId) {
  const companies = [
    Company(
      id: 'cmp-1',
      name: 'Mare Blu Srl',
      vatNumber: 'IT12345678901',
      taxCode: '12345678901',
      pec: 'amministrazione@pec.mareblu.it',
      sdiCode: 'MBS001',
      email: 'operations@mareblu.it',
      phone: '+39 02 1234 5678',
      website: 'https://mareblu.example',
      addressLine: 'Via del Porto 14',
      city: 'Milano',
      postalCode: '20121',
      country: 'Italia',
      contactPerson: 'Laura Bianchi',
      notes: 'Cliente premium con fatturazione mensile e revisione SLA.',
    ),
    Company(
      id: 'cmp-2',
      name: 'Northwind Studio',
      vatNumber: 'IT98765432109',
      taxCode: '98765432109',
      pec: 'finance@pec.northwind.it',
      sdiCode: 'NWIND9',
      email: 'hello@northwind.it',
      phone: '+39 06 8765 4321',
      website: 'https://northwind.example',
      addressLine: 'Piazza Europa 8',
      city: 'Roma',
      postalCode: '00144',
      country: 'Italia',
      contactPerson: 'Marco Conti',
      notes:
          'Studio creativo, approvazione preventivi via referente marketing.',
    ),
  ];

  const projects = [
    Project(
      id: 'prj-1',
      companyId: 'cmp-1',
      name: 'CRM Replatform',
      code: 'MB-CRM-26',
      status: 'active',
    ),
    Project(
      id: 'prj-2',
      companyId: 'cmp-2',
      name: 'Billing Automation',
      code: 'NW-BILL-12',
      status: 'active',
    ),
  ];

  const phases = [
    ProjectPhase(id: 'ph-1', projectId: 'prj-1', name: 'Design', order: 1),
    ProjectPhase(id: 'ph-2', projectId: 'prj-1', name: 'Development', order: 2),
    ProjectPhase(id: 'ph-3', projectId: 'prj-2', name: 'Review', order: 1),
  ];

  final now = DateTime.now();
  final tasks = [
    WorkTask(
      id: 'tsk-1',
      companyId: 'cmp-1',
      projectId: 'prj-1',
      phaseId: 'ph-2',
      assigneeId: userId,
      name: 'Kanban timeline for CRM onboarding',
      estimatedHours: 8,
      loggedHours: 1.5,
      startDate: now,
      deadline: now.add(const Duration(days: 3)),
      status: TaskStatus.inProgress,
      billable: true,
    ),
    WorkTask(
      id: 'tsk-2',
      companyId: 'cmp-1',
      projectId: 'prj-1',
      phaseId: 'ph-2',
      assigneeId: userId,
      name: 'Deadline-aware planning engine',
      estimatedHours: 10,
      loggedHours: 0,
      startDate: now,
      deadline: now.add(const Duration(days: 4)),
      status: TaskStatus.planned,
      billable: true,
    ),
    WorkTask(
      id: 'tsk-3',
      companyId: 'cmp-2',
      projectId: 'prj-2',
      phaseId: 'ph-3',
      assigneeId: userId,
      name: 'XML export for e-invoice handoff',
      estimatedHours: 4,
      loggedHours: 0,
      startDate: now,
      deadline: now.add(const Duration(days: 5)),
      status: TaskStatus.planned,
      billable: true,
    ),
  ];

  const availability = [
    UserAvailability(weekday: DateTime.monday, hours: 0, isOff: true),
    UserAvailability(weekday: DateTime.tuesday, hours: 4, isOff: false),
    UserAvailability(weekday: DateTime.wednesday, hours: 8, isOff: false),
    UserAvailability(weekday: DateTime.thursday, hours: 6, isOff: false),
    UserAvailability(weekday: DateTime.friday, hours: 5, isOff: false),
    UserAvailability(weekday: DateTime.saturday, hours: 0, isOff: true),
    UserAvailability(weekday: DateTime.sunday, hours: 0, isOff: true),
  ];

  final planner = const PlanningService();
  final alreadyPlanned = <DateTime, double>{};
  final plannedSlots = <TimelineSlot>[];

  for (final task in tasks) {
    final result = planner.distributeTask(
      task: task,
      startDate: task.startDate,
      endDate: task.deadline,
      weeklyAvailability: availability,
      blockedDates: const {},
      alreadyPlannedHours: alreadyPlanned,
    );
    plannedSlots.addAll(result.slots);
  }

  const invoiceDrafts = [
    InvoiceDraft(
      id: 'inv-1',
      companyId: 'cmp-1',
      number: '2026/041',
      amount: 3280,
      status: InvoiceStatus.readyForXml,
    ),
    InvoiceDraft(
      id: 'inv-2',
      companyId: 'cmp-2',
      number: '2026/042',
      amount: 1240,
      status: InvoiceStatus.draft,
    ),
  ];

  return DemoWorkspace(
    companies: companies,
    companyContacts: const [],
    tickets: const [],
    projects: projects,
    phases: phases,
    tasks: tasks,
    availability: availability,
    vacations: const [],
    plannedSlots: plannedSlots,
    timeTracks: const [],
    invoiceDrafts: invoiceDrafts,
  );
}
