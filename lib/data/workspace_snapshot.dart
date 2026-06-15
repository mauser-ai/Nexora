import '../models/domain_models.dart';

// WorkspaceSnapshot è la struttura dati centrale che contiene tutti i dati
// dell'utente in memoria. Usata sia dall'ApiWorkspaceRepository (SQL) che
// dall'eventuale FirestoreWorkspaceRepository legacy.

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
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
    required this.billingProfile,
    required this.emailSignatureHtml,
    required this.youdoxConfig,
    this.opportunities = const [],
    this.gussoniQuotations = const [],
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
  final BillingProfile billingProfile;
  final String emailSignatureHtml;
  final YouDoxConfig youdoxConfig;
  final List<Opportunity> opportunities;
  final List<Preventivo> gussoniQuotations;

  bool get isEmpty =>
      companies.isEmpty &&
      companyContacts.isEmpty &&
      tickets.isEmpty &&
      projects.isEmpty &&
      phases.isEmpty &&
      tasks.isEmpty &&
      availability.isEmpty &&
      vacations.isEmpty &&
      plannedSlots.isEmpty &&
      timeTracks.isEmpty &&
      invoiceDrafts.isEmpty &&
      !billingProfile.isConfigured;

  static const empty = WorkspaceSnapshot(
    companies: [],
    companyContacts: [],
    tickets: [],
    projects: [],
    phases: [],
    tasks: [],
    availability: [],
    vacations: [],
    plannedSlots: [],
    timeTracks: [],
    invoiceDrafts: [],
    billingProfile: BillingProfile.empty,
    emailSignatureHtml: '',
    youdoxConfig: YouDoxConfig.empty,
    opportunities: [],
    gussoniQuotations: [],
  );

  WorkspaceSnapshot copyWith({
    List<Company>? companies,
    List<CompanyContact>? companyContacts,
    List<Ticket>? tickets,
    List<Project>? projects,
    List<ProjectPhase>? phases,
    List<WorkTask>? tasks,
    List<UserAvailability>? availability,
    List<VacationPeriod>? vacations,
    List<TimelineSlot>? plannedSlots,
    List<TimeTrack>? timeTracks,
    List<InvoiceDraft>? invoiceDrafts,
    BillingProfile? billingProfile,
    String? emailSignatureHtml,
    YouDoxConfig? youdoxConfig,
    List<Opportunity>? opportunities,
    List<Preventivo>? gussoniQuotations,
  }) {
    return WorkspaceSnapshot(
      companies: companies ?? this.companies,
      companyContacts: companyContacts ?? this.companyContacts,
      tickets: tickets ?? this.tickets,
      projects: projects ?? this.projects,
      phases: phases ?? this.phases,
      tasks: tasks ?? this.tasks,
      availability: availability ?? this.availability,
      vacations: vacations ?? this.vacations,
      plannedSlots: plannedSlots ?? this.plannedSlots,
      timeTracks: timeTracks ?? this.timeTracks,
      invoiceDrafts: invoiceDrafts ?? this.invoiceDrafts,
      billingProfile: billingProfile ?? this.billingProfile,
      emailSignatureHtml: emailSignatureHtml ?? this.emailSignatureHtml,
      youdoxConfig: youdoxConfig ?? this.youdoxConfig,
      opportunities: opportunities ?? this.opportunities,
      gussoniQuotations: gussoniQuotations ?? this.gussoniQuotations,
    );
  }
}
