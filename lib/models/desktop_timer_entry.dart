class DesktopTimerEntry {
  const DesktopTimerEntry({
    required this.id,
    required this.startedAt,
    this.stoppedAt,
    this.taskId = '',
    this.companyId = '',
    this.projectId = '',
    this.name = '',
    this.description = '',
  });

  final String id;
  final DateTime startedAt;
  final DateTime? stoppedAt;
  final String taskId;
  final String companyId;
  final String projectId;
  final String name;
  final String description;

  bool get isRunning => stoppedAt == null;

  DesktopTimerEntry copyWith({
    DateTime? startedAt,
    DateTime? stoppedAt,
    String? taskId,
    String? companyId,
    String? projectId,
    String? name,
    String? description,
  }) => DesktopTimerEntry(
    id: id,
    startedAt: startedAt ?? this.startedAt,
    stoppedAt: stoppedAt ?? this.stoppedAt,
    taskId: taskId ?? this.taskId,
    companyId: companyId ?? this.companyId,
    projectId: projectId ?? this.projectId,
    name: name ?? this.name,
    description: description ?? this.description,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'stoppedAt': stoppedAt?.toIso8601String(),
    'taskId': taskId,
    'companyId': companyId,
    'projectId': projectId,
    'name': name,
    'description': description,
  };

  factory DesktopTimerEntry.fromMap(Map<String, dynamic> map) =>
      DesktopTimerEntry(
        id: map['id'] as String? ?? '',
        startedAt:
            DateTime.tryParse(map['startedAt'] as String? ?? '') ??
            DateTime.now(),
        stoppedAt: (map['stoppedAt'] as String?)?.isNotEmpty == true
            ? DateTime.tryParse(map['stoppedAt'] as String)
            : null,
        taskId: map['taskId'] as String? ?? '',
        companyId: map['companyId'] as String? ?? '',
        projectId: map['projectId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        description: map['description'] as String? ?? '',
      );
}
