enum CustomFieldModule {
  companies,
  contacts,
  opportunities,
  projects;

  String get storageKey => switch (this) {
    CustomFieldModule.companies => 'companies',
    CustomFieldModule.contacts => 'contacts',
    CustomFieldModule.opportunities => 'opportunities',
    CustomFieldModule.projects => 'projects',
  };

  String get label => switch (this) {
    CustomFieldModule.companies => 'Societa',
    CustomFieldModule.contacts => 'Contatti',
    CustomFieldModule.opportunities => 'Opportunita',
    CustomFieldModule.projects => 'Progetti',
  };

  static CustomFieldModule? tryParse(String? raw) {
    for (final value in values) {
      if (value.storageKey == raw) return value;
    }
    return null;
  }
}

enum CustomFieldType {
  text,
  textarea,
  select;

  String get storageKey => switch (this) {
    CustomFieldType.text => 'text',
    CustomFieldType.textarea => 'textarea',
    CustomFieldType.select => 'select',
  };

  String get label => switch (this) {
    CustomFieldType.text => 'Input',
    CustomFieldType.textarea => 'Textarea',
    CustomFieldType.select => 'Select',
  };

  static CustomFieldType? tryParse(String? raw) {
    for (final value in values) {
      if (value.storageKey == raw) return value;
    }
    return null;
  }
}

class TeamCustomFieldDefinition {
  const TeamCustomFieldDefinition({
    required this.id,
    required this.module,
    required this.label,
    required this.type,
    this.maxLength = 255,
    this.options = const [],
  });

  final String id;
  final CustomFieldModule module;
  final String label;
  final CustomFieldType type;
  final int maxLength;
  final List<String> options;

  bool get isSelect => type == CustomFieldType.select;
  bool get isTextarea => type == CustomFieldType.textarea;

  factory TeamCustomFieldDefinition.fromMap(Map<String, dynamic> map) {
    final module = CustomFieldModule.tryParse(map['module']?.toString());
    final type = CustomFieldType.tryParse(map['type']?.toString());
    final options = ((map['options'] as List?) ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return TeamCustomFieldDefinition(
      id: map['id']?.toString() ?? '',
      module: module ?? CustomFieldModule.companies,
      label: map['label']?.toString() ?? '',
      type: type ?? CustomFieldType.text,
      maxLength: (map['maxLength'] as num?)?.toInt() ?? 255,
      options: options,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'module': module.storageKey,
    'label': label,
    'type': type.storageKey,
    'maxLength': maxLength,
    'options': options,
  };

  TeamCustomFieldDefinition copyWith({
    String? id,
    CustomFieldModule? module,
    String? label,
    CustomFieldType? type,
    int? maxLength,
    List<String>? options,
  }) {
    return TeamCustomFieldDefinition(
      id: id ?? this.id,
      module: module ?? this.module,
      label: label ?? this.label,
      type: type ?? this.type,
      maxLength: maxLength ?? this.maxLength,
      options: options ?? this.options,
    );
  }
}

Map<String, dynamic> normalizeCustomFieldValues(dynamic raw) {
  if (raw is! Map) return const <String, dynamic>{};
  final normalized = <String, dynamic>{};
  raw.forEach((key, value) {
    final id = key.toString().trim();
    if (id.isEmpty || value == null) return;
    final stringValue = value.toString().trim();
    if (stringValue.isEmpty) return;
    normalized[id] = stringValue;
  });
  return normalized;
}
