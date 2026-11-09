import 'package:flutter/material.dart';

import '../brand_config.dart';
import '../models/custom_field_models.dart';

class CustomFieldsSection extends StatelessWidget {
  const CustomFieldsSection({
    super.key,
    required this.definitions,
    required this.controllers,
    required this.selectValues,
    required this.onSelectChanged,
    this.title = 'Campi personalizzati',
    this.compact = false,
  });

  final List<TeamCustomFieldDefinition> definitions;
  final Map<String, TextEditingController> controllers;
  final Map<String, String?> selectValues;
  final void Function(String fieldId, String? value) onSelectChanged;
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (definitions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: GussoniBrand.textMuted,
              letterSpacing: 0.6,
            ),
          ),
        ),
        ...definitions.map((definition) {
          if (definition.type == CustomFieldType.select) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                value: selectValues[definition.id],
                decoration: InputDecoration(
                  labelText: definition.label,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('— Nessun valore —'),
                  ),
                  ...definition.options.map(
                    (option) =>
                        DropdownMenuItem(value: option, child: Text(option)),
                  ),
                ],
                onChanged: (value) => onSelectChanged(
                  definition.id,
                  (value == null || value.isEmpty) ? null : value,
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: controllers[definition.id],
              maxLines: definition.isTextarea ? (compact ? 3 : 4) : 1,
              maxLength: definition.maxLength,
              decoration: InputDecoration(
                labelText: definition.label,
                helperText: 'Max ${definition.maxLength} caratteri',
                border: const OutlineInputBorder(),
              ),
            ),
          );
        }),
      ],
    );
  }
}
