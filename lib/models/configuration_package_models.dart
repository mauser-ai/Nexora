import 'custom_field_models.dart';
import 'roles.dart';

enum ConfigurationPackageType {
  sector,
  customFields;

  String get storageKey => switch (this) {
    ConfigurationPackageType.sector => 'sector',
    ConfigurationPackageType.customFields => 'custom_fields',
  };

  String get label => switch (this) {
    ConfigurationPackageType.sector => 'Pacchetto settore',
    ConfigurationPackageType.customFields => 'Pacchetto custom fields',
  };

  static ConfigurationPackageType? tryParse(String? raw) {
    for (final value in values) {
      if (value.storageKey == raw) return value;
    }
    return null;
  }
}

class ConfigurationPackage {
  const ConfigurationPackage({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    this.icon = '',
    this.color = '',
    this.enabledModules = const [],
    this.teamRoles = const [],
    this.customFieldDefinitions = const [],
    this.metadata = const <String, dynamic>{},
    this.active = true,
    this.system = true,
  });

  final String id;
  final ConfigurationPackageType type;
  final String name;
  final String description;
  final String icon;
  final String color;
  final List<String> enabledModules;
  final List<String> teamRoles;
  final List<TeamCustomFieldDefinition> customFieldDefinitions;
  final Map<String, dynamic> metadata;
  final bool active;
  final bool system;

  factory ConfigurationPackage.fromMap(Map<dynamic, dynamic> map) {
    return ConfigurationPackage(
      id: (map['id'] ?? '').toString(),
      type:
          ConfigurationPackageType.tryParse(map['type']?.toString()) ??
          ConfigurationPackageType.customFields,
      name: (map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      icon: (map['icon'] ?? '').toString(),
      color: (map['color'] ?? '').toString(),
      enabledModules: ((map['enabledModules'] as List?) ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      teamRoles: GussoniRoles.normalize(
        ((map['teamRoles'] as List?) ?? const []).map(
          (value) => value.toString(),
        ),
      ),
      customFieldDefinitions:
          ((map['customFieldDefinitions'] as List?) ?? const [])
              .whereType<Map>()
              .map(
                (field) => TeamCustomFieldDefinition.fromMap(
                  Map<String, dynamic>.from(field),
                ),
              )
              .where((field) => field.id.isNotEmpty && field.label.isNotEmpty)
              .toList(),
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const <String, dynamic>{},
      active: map['active'] as bool? ?? true,
      system: map['system'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.storageKey,
    'name': name,
    'description': description,
    'icon': icon,
    'color': color,
    'enabledModules': enabledModules,
    'teamRoles': teamRoles,
    'customFieldDefinitions': customFieldDefinitions
        .map((field) => field.toMap())
        .toList(),
    'metadata': metadata,
    'active': active,
    'system': system,
  };

  ConfigurationPackage copyWith({
    String? id,
    ConfigurationPackageType? type,
    String? name,
    String? description,
    String? icon,
    String? color,
    List<String>? enabledModules,
    List<String>? teamRoles,
    List<TeamCustomFieldDefinition>? customFieldDefinitions,
    Map<String, dynamic>? metadata,
    bool? active,
    bool? system,
  }) {
    return ConfigurationPackage(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      enabledModules: enabledModules ?? this.enabledModules,
      teamRoles: teamRoles ?? this.teamRoles,
      customFieldDefinitions:
          customFieldDefinitions ?? this.customFieldDefinitions,
      metadata: metadata ?? this.metadata,
      active: active ?? this.active,
      system: system ?? this.system,
    );
  }
}
