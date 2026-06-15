import '../../brand_config.dart';
import 'package:flutter/material.dart';

// ────────────────────────────────────────────────
// Enums
// ────────────────────────────────────────────────

enum TeamMemberRole { owner, admin, manager, member, viewer }

enum TeamMemberStatus { invited, active, suspended }

enum DealStatus { open, won, lost }

enum CrmTaskStatus { open, inProgress, waiting, done, cancelled }

enum CrmTaskPriority { low, medium, high, urgent }

enum CrmProjectStatus { planned, running, overdue, overBudget, closed }

enum CrmQuotationStatus { draft, sent, accepted, rejected }

enum CrmInvoiceStatus { draft, booked, sent, paid, overdue }

enum CrmActivityActionType {
  created,
  updated,
  statusChanged,
  commented,
  noteAdded,
  taskCreated,
  taskCompleted,
  dealMoved,
}

// ────────────────────────────────────────────────
// Enum extensions (labels + colors)
// ────────────────────────────────────────────────

extension TeamMemberRoleX on TeamMemberRole {
  String get label {
    switch (this) {
      case TeamMemberRole.owner:
        return 'Proprietario';
      case TeamMemberRole.admin:
        return 'Amministratore';
      case TeamMemberRole.manager:
        return 'Manager';
      case TeamMemberRole.member:
        return 'Membro';
      case TeamMemberRole.viewer:
        return 'Visualizzatore';
    }
  }

  Color get color {
    switch (this) {
      case TeamMemberRole.owner:
        return const Color(0xFF7C3AED);
      case TeamMemberRole.admin:
        return const Color(0xFF0369A1);
      case TeamMemberRole.manager:
        return const Color(0xFF065F46);
      case TeamMemberRole.member:
        return const Color(0xFFB8C0D8);
      case TeamMemberRole.viewer:
        return const Color(0xFF7D89A8);
    }
  }
}

extension DealStatusX on DealStatus {
  String get label {
    switch (this) {
      case DealStatus.open:
        return 'Aperto';
      case DealStatus.won:
        return 'Vinto';
      case DealStatus.lost:
        return 'Perso';
    }
  }

  Color get color {
    switch (this) {
      case DealStatus.open:
        return const Color(0xFF0369A1);
      case DealStatus.won:
        return GussoniBrand.primary;
      case DealStatus.lost:
        return const Color(0xFFB91C1C);
    }
  }
}

extension CrmTaskStatusX on CrmTaskStatus {
  String get label {
    switch (this) {
      case CrmTaskStatus.open:
        return 'Aperto';
      case CrmTaskStatus.inProgress:
        return 'In corso';
      case CrmTaskStatus.waiting:
        return 'In attesa';
      case CrmTaskStatus.done:
        return 'Fatto';
      case CrmTaskStatus.cancelled:
        return 'Annullato';
    }
  }

  Color get color {
    switch (this) {
      case CrmTaskStatus.open:
        return const Color(0xFFB8C0D8);
      case CrmTaskStatus.inProgress:
        return const Color(0xFF0369A1);
      case CrmTaskStatus.waiting:
        return const Color(0xFFD97706);
      case CrmTaskStatus.done:
        return GussoniBrand.primary;
      case CrmTaskStatus.cancelled:
        return const Color(0xFF7D89A8);
    }
  }
}

extension CrmTaskPriorityX on CrmTaskPriority {
  String get label {
    switch (this) {
      case CrmTaskPriority.low:
        return 'Bassa';
      case CrmTaskPriority.medium:
        return 'Media';
      case CrmTaskPriority.high:
        return 'Alta';
      case CrmTaskPriority.urgent:
        return 'Urgente';
    }
  }

  Color get color {
    switch (this) {
      case CrmTaskPriority.low:
        return const Color(0xFF7D89A8);
      case CrmTaskPriority.medium:
        return const Color(0xFF0369A1);
      case CrmTaskPriority.high:
        return const Color(0xFFD97706);
      case CrmTaskPriority.urgent:
        return const Color(0xFFB91C1C);
    }
  }
}

extension CrmProjectStatusX on CrmProjectStatus {
  String get label {
    switch (this) {
      case CrmProjectStatus.planned:
        return 'Pianificato';
      case CrmProjectStatus.running:
        return 'In corso';
      case CrmProjectStatus.overdue:
        return 'In ritardo';
      case CrmProjectStatus.overBudget:
        return 'Over budget';
      case CrmProjectStatus.closed:
        return 'Chiuso';
    }
  }

  Color get color {
    switch (this) {
      case CrmProjectStatus.planned:
        return const Color(0xFF7D89A8);
      case CrmProjectStatus.running:
        return const Color(0xFF0369A1);
      case CrmProjectStatus.overdue:
        return const Color(0xFFB91C1C);
      case CrmProjectStatus.overBudget:
        return const Color(0xFFD97706);
      case CrmProjectStatus.closed:
        return GussoniBrand.primary;
    }
  }
}

extension CrmQuotationStatusX on CrmQuotationStatus {
  String get label {
    switch (this) {
      case CrmQuotationStatus.draft:
        return 'Bozza';
      case CrmQuotationStatus.sent:
        return 'Inviato';
      case CrmQuotationStatus.accepted:
        return 'Accettato';
      case CrmQuotationStatus.rejected:
        return 'Rifiutato';
    }
  }

  Color get color {
    switch (this) {
      case CrmQuotationStatus.draft:
        return const Color(0xFF7D89A8);
      case CrmQuotationStatus.sent:
        return const Color(0xFF0369A1);
      case CrmQuotationStatus.accepted:
        return GussoniBrand.primary;
      case CrmQuotationStatus.rejected:
        return const Color(0xFFB91C1C);
    }
  }
}

extension CrmInvoiceStatusX on CrmInvoiceStatus {
  String get label {
    switch (this) {
      case CrmInvoiceStatus.draft:
        return 'Bozza';
      case CrmInvoiceStatus.booked:
        return 'Registrata';
      case CrmInvoiceStatus.sent:
        return 'Inviata';
      case CrmInvoiceStatus.paid:
        return 'Pagata';
      case CrmInvoiceStatus.overdue:
        return 'Scaduta';
    }
  }

  Color get color {
    switch (this) {
      case CrmInvoiceStatus.draft:
        return const Color(0xFF7D89A8);
      case CrmInvoiceStatus.booked:
        return const Color(0xFF7C3AED);
      case CrmInvoiceStatus.sent:
        return const Color(0xFF0369A1);
      case CrmInvoiceStatus.paid:
        return GussoniBrand.primary;
      case CrmInvoiceStatus.overdue:
        return const Color(0xFFB91C1C);
    }
  }
}

// ────────────────────────────────────────────────
// Team
// ────────────────────────────────────────────────

class CrmTeam {
  const CrmTeam({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.members,
    required this.createdAt,
    this.logo,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? logo;
  final String ownerId;
  final List<String> members;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CrmTeam copyWith({
    String? id,
    String? name,
    String? logo,
    String? ownerId,
    List<String>? members,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CrmTeam(
      id: id ?? this.id,
      name: name ?? this.name,
      logo: logo ?? this.logo,
      ownerId: ownerId ?? this.ownerId,
      members: members ?? this.members,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CrmTeamMember {
  const CrmTeamMember({
    required this.id,
    required this.userId,
    required this.teamId,
    required this.role,
    required this.status,
    this.invitedAt,
    this.joinedAt,
  });

  final String id;
  final String userId;
  final String teamId;
  final TeamMemberRole role;
  final TeamMemberStatus status;
  final DateTime? invitedAt;
  final DateTime? joinedAt;

  CrmTeamMember copyWith({
    TeamMemberRole? role,
    TeamMemberStatus? status,
  }) {
    return CrmTeamMember(
      id: id,
      userId: userId,
      teamId: teamId,
      role: role ?? this.role,
      status: status ?? this.status,
      invitedAt: invitedAt,
      joinedAt: joinedAt,
    );
  }
}

// ────────────────────────────────────────────────
// User
// ────────────────────────────────────────────────

class CrmUser {
  const CrmUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.avatar,
    this.phone,
    this.createdAt,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? avatar;
  final String? phone;
  final DateTime? createdAt;

  String get fullName => '$firstName $lastName';

  String get initials {
    final f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l';
  }
}

// ────────────────────────────────────────────────
// CRM Company
// ────────────────────────────────────────────────

class CrmCompany {
  const CrmCompany({
    required this.id,
    required this.teamId,
    required this.name,
    this.vatNumber = '',
    this.email = '',
    this.phone = '',
    this.website = '',
    this.address = '',
    this.tags = const [],
    this.assignedTo,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String teamId;
  final String name;
  final String vatNumber;
  final String email;
  final String phone;
  final String website;
  final String address;
  final List<String> tags;
  final String? assignedTo;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get initials {
    final words = name.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  CrmCompany copyWith({
    String? name,
    String? vatNumber,
    String? email,
    String? phone,
    String? website,
    String? address,
    List<String>? tags,
    String? assignedTo,
    String? createdBy,
  }) {
    return CrmCompany(
      id: id,
      teamId: teamId,
      name: name ?? this.name,
      vatNumber: vatNumber ?? this.vatNumber,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      website: website ?? this.website,
      address: address ?? this.address,
      tags: tags ?? this.tags,
      assignedTo: assignedTo ?? this.assignedTo,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

// ────────────────────────────────────────────────
// CRM Contact
// ────────────────────────────────────────────────

class CrmContact {
  const CrmContact({
    required this.id,
    required this.teamId,
    required this.firstName,
    required this.lastName,
    this.companyId,
    this.email = '',
    this.phone = '',
    this.role = '',
    this.tags = const [],
    this.assignedTo,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String teamId;
  final String firstName;
  final String lastName;
  final String? companyId;
  final String email;
  final String phone;
  final String role;
  final List<String> tags;
  final String? assignedTo;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get fullName => '$firstName $lastName';

  String get initials {
    final f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l';
  }

  CrmContact copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? role,
    String? companyId,
    String? assignedTo,
  }) {
    return CrmContact(
      id: id,
      teamId: teamId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      companyId: companyId ?? this.companyId,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      tags: tags,
      assignedTo: assignedTo ?? this.assignedTo,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

// ────────────────────────────────────────────────
// Pipeline & Deal
// ────────────────────────────────────────────────

class CrmPipelineStage {
  const CrmPipelineStage({
    required this.id,
    required this.teamId,
    required this.name,
    required this.order,
    required this.color,
    this.probability = 0,
  });

  final String id;
  final String teamId;
  final String name;
  final int order;
  final Color color;
  final int probability;
}

class CrmDeal {
  const CrmDeal({
    required this.id,
    required this.teamId,
    required this.title,
    required this.stageId,
    required this.status,
    required this.value,
    this.currency = 'EUR',
    this.customerId,
    this.customerType,
    this.probability = 0,
    this.expectedClosingDate,
    this.assignedTo,
    this.createdBy,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String teamId;
  final String title;
  final String stageId;
  final DealStatus status;
  final double value;
  final String currency;
  final String? customerId;
  final String? customerType;
  final int probability;
  final DateTime? expectedClosingDate;
  final String? assignedTo;
  final String? createdBy;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CrmDeal copyWith({
    String? title,
    String? stageId,
    DealStatus? status,
    double? value,
    int? probability,
    String? assignedTo,
    String? notes,
    DateTime? expectedClosingDate,
  }) {
    return CrmDeal(
      id: id,
      teamId: teamId,
      title: title ?? this.title,
      stageId: stageId ?? this.stageId,
      status: status ?? this.status,
      value: value ?? this.value,
      currency: currency,
      customerId: customerId,
      customerType: customerType,
      probability: probability ?? this.probability,
      expectedClosingDate: expectedClosingDate ?? this.expectedClosingDate,
      assignedTo: assignedTo ?? this.assignedTo,
      createdBy: createdBy,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

// ────────────────────────────────────────────────
// CRM Task
// ────────────────────────────────────────────────

class CrmTask {
  const CrmTask({
    required this.id,
    required this.teamId,
    required this.title,
    required this.status,
    required this.priority,
    this.description = '',
    this.assignedTo,
    this.createdBy,
    this.relatedEntityType,
    this.relatedEntityId,
    this.dueDate,
    this.commentsCount = 0,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String teamId;
  final String title;
  final String description;
  final CrmTaskStatus status;
  final CrmTaskPriority priority;
  final String? assignedTo;
  final String? createdBy;
  final String? relatedEntityType;
  final String? relatedEntityId;
  final DateTime? dueDate;
  final int commentsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  bool get isOverdue {
    if (dueDate == null || status == CrmTaskStatus.done) {
      return false;
    }
    return dueDate!.isBefore(DateTime.now());
  }

  CrmTask copyWith({
    String? title,
    String? description,
    CrmTaskStatus? status,
    CrmTaskPriority? priority,
    String? assignedTo,
    DateTime? dueDate,
    DateTime? completedAt,
  }) {
    return CrmTask(
      id: id,
      teamId: teamId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      assignedTo: assignedTo ?? this.assignedTo,
      createdBy: createdBy,
      relatedEntityType: relatedEntityType,
      relatedEntityId: relatedEntityId,
      dueDate: dueDate ?? this.dueDate,
      commentsCount: commentsCount,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

// ────────────────────────────────────────────────
// Comment & Note
// ────────────────────────────────────────────────

class CrmComment {
  const CrmComment({
    required this.id,
    required this.teamId,
    required this.entityType,
    required this.entityId,
    required this.authorId,
    required this.body,
    this.mentions = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String teamId;
  final String entityType;
  final String entityId;
  final String authorId;
  final String body;
  final List<String> mentions;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class CrmNote {
  const CrmNote({
    required this.id,
    required this.teamId,
    required this.entityType,
    required this.entityId,
    required this.authorId,
    required this.body,
    this.isPinned = false,
    this.visibility = 'team',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String teamId;
  final String entityType;
  final String entityId;
  final String authorId;
  final String body;
  final bool isPinned;
  final String visibility;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

// ────────────────────────────────────────────────
// Project & Milestone
// ────────────────────────────────────────────────

class CrmProject {
  const CrmProject({
    required this.id,
    required this.teamId,
    required this.title,
    required this.status,
    required this.ownerId,
    this.description = '',
    this.customerId,
    this.customerType,
    this.members = const [],
    this.startDate,
    this.endDate,
    this.budget = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String teamId;
  final String title;
  final String description;
  final CrmProjectStatus status;
  final String ownerId;
  final String? customerId;
  final String? customerType;
  final List<String> members;
  final DateTime? startDate;
  final DateTime? endDate;
  final double budget;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class CrmMilestone {
  const CrmMilestone({
    required this.id,
    required this.teamId,
    required this.projectId,
    required this.title,
    required this.status,
    this.description = '',
    this.responsibleUserId,
    this.dueDate,
  });

  final String id;
  final String teamId;
  final String projectId;
  final String title;
  final String description;
  final String status;
  final String? responsibleUserId;
  final DateTime? dueDate;
}

// ────────────────────────────────────────────────
// Quotation & Invoice
// ────────────────────────────────────────────────

class CrmLineItem {
  const CrmLineItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.vatRate = 22.0,
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double vatRate;

  double get net => quantity * unitPrice;
  double get vat => net * (vatRate / 100);
  double get total => net + vat;
}

class CrmQuotation {
  const CrmQuotation({
    required this.id,
    required this.teamId,
    required this.number,
    required this.status,
    required this.lines,
    this.customerId,
    this.customerType,
    this.currency = 'EUR',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String teamId;
  final String number;
  final CrmQuotationStatus status;
  final List<CrmLineItem> lines;
  final String? customerId;
  final String? customerType;
  final String currency;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get total => lines.fold(0, (sum, l) => sum + l.total);
}

class CrmInvoice {
  const CrmInvoice({
    required this.id,
    required this.teamId,
    required this.number,
    required this.status,
    required this.lines,
    this.customerId,
    this.customerType,
    this.currency = 'EUR',
    this.dueDate,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String teamId;
  final String number;
  final CrmInvoiceStatus status;
  final List<CrmLineItem> lines;
  final String? customerId;
  final String? customerType;
  final String currency;
  final DateTime? dueDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get total => lines.fold(0, (sum, l) => sum + l.total);
}

// ────────────────────────────────────────────────
// Activity Timeline
// ────────────────────────────────────────────────

class CrmActivityItem {
  const CrmActivityItem({
    required this.id,
    required this.teamId,
    required this.entityType,
    required this.entityId,
    required this.actorId,
    required this.actionType,
    required this.title,
    this.description = '',
    this.metadata = const {},
    this.createdAt,
  });

  final String id;
  final String teamId;
  final String entityType;
  final String entityId;
  final String actorId;
  final CrmActivityActionType actionType;
  final String title;
  final String description;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  IconData get icon {
    switch (actionType) {
      case CrmActivityActionType.created:
        return Icons.add_circle_outline;
      case CrmActivityActionType.updated:
        return Icons.edit_outlined;
      case CrmActivityActionType.statusChanged:
        return Icons.swap_horiz_outlined;
      case CrmActivityActionType.commented:
        return Icons.chat_bubble_outline;
      case CrmActivityActionType.noteAdded:
        return Icons.sticky_note_2_outlined;
      case CrmActivityActionType.taskCreated:
        return Icons.task_alt_outlined;
      case CrmActivityActionType.taskCompleted:
        return Icons.check_circle_outline;
      case CrmActivityActionType.dealMoved:
        return Icons.arrow_forward_outlined;
    }
  }

  Color get iconColor {
    switch (actionType) {
      case CrmActivityActionType.created:
        return GussoniBrand.primary;
      case CrmActivityActionType.updated:
        return const Color(0xFF0369A1);
      case CrmActivityActionType.statusChanged:
        return const Color(0xFF7C3AED);
      case CrmActivityActionType.commented:
        return const Color(0xFF0369A1);
      case CrmActivityActionType.noteAdded:
        return const Color(0xFFD97706);
      case CrmActivityActionType.taskCreated:
        return const Color(0xFFB8C0D8);
      case CrmActivityActionType.taskCompleted:
        return GussoniBrand.primary;
      case CrmActivityActionType.dealMoved:
        return const Color(0xFF7C3AED);
    }
  }
}
