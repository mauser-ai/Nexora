import 'dart:async';

import 'package:flutter/material.dart';

import '../../brand_config.dart';
import '../../data/api_workspace_repository.dart';
import '../../data/team_repository.dart';
import '../../models/custom_field_models.dart';
import '../../models/domain_models.dart';
import '../../services/archive_service.dart';
import '../../app/nexora_dialog.dart';
import '../../widgets/custom_fields_section.dart';

Map<String, TextEditingController> _buildProjectCustomFieldControllers(
  List<TeamCustomFieldDefinition> definitions,
) {
  final controllers = <String, TextEditingController>{};
  for (final definition in definitions) {
    if (definition.type == CustomFieldType.select) continue;
    controllers[definition.id] = TextEditingController();
  }
  return controllers;
}

Map<String, String?> _buildProjectCustomFieldSelectValues(
  List<TeamCustomFieldDefinition> definitions,
) {
  final values = <String, String?>{};
  for (final definition in definitions) {
    if (definition.type == CustomFieldType.select) {
      values[definition.id] = null;
    }
  }
  return values;
}

Map<String, dynamic> _collectProjectCustomFieldValues(
  List<TeamCustomFieldDefinition> definitions,
  Map<String, TextEditingController> controllers,
  Map<String, String?> selectValues,
) {
  final values = <String, dynamic>{};
  for (final definition in definitions) {
    if (definition.type == CustomFieldType.select) {
      final value = selectValues[definition.id]?.trim();
      if (value != null && value.isNotEmpty) values[definition.id] = value;
      continue;
    }
    final value = controllers[definition.id]?.text.trim() ?? '';
    if (value.isNotEmpty) values[definition.id] = value;
  }
  return values;
}

class ProjectWizardDialog extends StatefulWidget {
  const ProjectWizardDialog({
    super.key,
    required this.projectName,
    required this.projectType,
    required this.companyId,
    required this.userId,
    required this.repository,
    required this.teamMembers,
    required this.onCreated,
    this.opportunityId,
    this.quotationId,
    this.companyName,
    this.templates = const [],
    this.customFieldDefinitions = const [],
  });

  final String projectName;
  final ProjectType projectType;
  final String companyId;
  final String? companyName;
  final String? opportunityId;
  final String? quotationId;
  final String userId;
  final ApiWorkspaceRepository repository;
  final List<TeamMember> teamMembers;
  final void Function(String projectId) onCreated;
  final List<ProjectTemplate> templates;
  final List<TeamCustomFieldDefinition> customFieldDefinitions;

  @override
  State<ProjectWizardDialog> createState() => _ProjectWizardDialogState();
}

class _ProjectWizardDialogState extends State<ProjectWizardDialog> {
  final _archiveService = ArchiveService();
  bool _saving = false;
  String? _selectedTemplateId;
  late final Map<String, TextEditingController> _customFieldControllers;
  late final Map<String, String?> _customFieldSelectValues;

  List<ProjectTemplate> get _templates {
    final customs = widget.templates
        .where(
          (t) => t.id != kStandardProjectTemplate.id && t.isDefault != true,
        )
        .toList();
    return customs;
  }

  ProjectTemplate? get _selectedTemplate =>
      _templates.where((t) => t.id == _selectedTemplateId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _customFieldControllers = _buildProjectCustomFieldControllers(
      widget.customFieldDefinitions,
    );
    _customFieldSelectValues = _buildProjectCustomFieldSelectValues(
      widget.customFieldDefinitions,
    );
  }

  @override
  void dispose() {
    for (final controller in _customFieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _createProject() async {
    setState(() => _saving = true);
    final projectId = 'prj-${DateTime.now().microsecondsSinceEpoch}';
    final customFields = _collectProjectCustomFieldValues(
      widget.customFieldDefinitions,
      _customFieldControllers,
      _customFieldSelectValues,
    );
    try {
      if (_selectedTemplate == null) {
        await widget.repository.createProject(
          widget.userId,
          Project(
            id: projectId,
            companyId: widget.companyId,
            name: widget.projectName,
            code: '',
            status: ProjectStatus.draft.name,
            type: widget.projectType,
            opportunityId: widget.opportunityId,
            quotationId: widget.quotationId,
            customFields: customFields,
          ),
        );
      } else {
        await widget.repository.createProjectWithConfig(
          userId: widget.userId,
          projectId: projectId,
          name: widget.projectName,
          companyId: widget.companyId,
          phaseConfigs: _selectedTemplate!.toPhaseConfigs(),
          type: widget.projectType,
          opportunityId: widget.opportunityId,
          quotationId: widget.quotationId,
          customFields: customFields,
        );
      }

      final companyName = widget.companyName?.trim() ?? '';
      if (companyName.isNotEmpty) {
        final phaseNames =
            _selectedTemplate?.phases
                .map((phase) => phase.name.trim())
                .where((name) => name.isNotEmpty)
                .toList() ??
            const <String>[];
        unawaited(
          _archiveService
              .createProjectStructure(
                companyName: companyName,
                projectName: widget.projectName,
                phaseNames: phaseNames,
              )
              .catchError((_) {}),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCreated(projectId);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore creazione progetto: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTemplate = _selectedTemplate;
    final phaseCount = selectedTemplate?.phases.length ?? 0;
    final taskCount =
        selectedTemplate?.phases.fold<int>(
          0,
          (sum, phase) => sum + phase.tasks.length,
        ) ??
        0;

    return NexoraAdaptiveDialogFrame(
      title: 'Crea progetto',
      icon: Icons.folder_open_outlined,
      width: 760,
      contentPadding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.folder_open_outlined, color: GussoniBrand.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.projectName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: GussoniBrand.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.companyName?.isNotEmpty == true
                              ? '${widget.companyName} · scegli come iniziare il progetto'
                              : 'Scegli se partire da un template o da un progetto vuoto.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Modalità creazione',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CreationChoiceCard(
                      title: 'Progetto vuoto',
                      subtitle:
                          'Crea solo il progetto. Fasi, task, date e assegnatari li aggiungi dopo dentro il progetto.',
                      selected: _selectedTemplateId == null,
                      icon: Icons.note_add_outlined,
                      badge: 'Vuoto',
                      onTap: _saving
                          ? null
                          : () => setState(() => _selectedTemplateId = null),
                    ),
                    const SizedBox(height: 12),
                    if (_templates.isNotEmpty) ...[
                      const Text(
                        'Template progetto',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._templates.map(
                        (template) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CreationChoiceCard(
                            title: template.name,
                            subtitle:
                                '${template.phases.length} fasi · ${template.phases.fold<int>(0, (sum, phase) => sum + phase.tasks.length)} task',
                            selected: _selectedTemplateId == template.id,
                            icon: Icons.account_tree_outlined,
                            badge: 'Template',
                            onTap: _saving
                                ? null
                                : () => setState(
                                    () => _selectedTemplateId = template.id,
                                  ),
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: GussoniBrand.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: GussoniBrand.border),
                        ),
                        child: const Text(
                          'Questo team non ha ancora template progetto. Puoi creare il progetto vuoto e strutturarlo dopo.',
                          style: TextStyle(
                            fontSize: 13,
                            color: GussoniBrand.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: GussoniBrand.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: GussoniBrand.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Anteprima struttura',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: GussoniBrand.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (selectedTemplate == null)
                            const Text(
                              'Nessuna fase preimpostata. Dopo la creazione potrai aggiungere fasi e task dal dettaglio progetto.',
                              style: TextStyle(
                                fontSize: 13,
                                color: GussoniBrand.textSecondary,
                              ),
                            )
                          else ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoPill(label: '$phaseCount fasi'),
                                _InfoPill(label: '$taskCount task'),
                                const _InfoPill(
                                  label: 'Nessuna data precompilata',
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ...selectedTemplate.phases.map(
                              (phase) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      phase.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: GussoniBrand.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      phase.tasks.isEmpty
                                          ? 'Nessun task predefinito'
                                          : phase.tasks.join(' · '),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: GussoniBrand.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.customFieldDefinitions.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      CustomFieldsSection(
                        definitions: widget.customFieldDefinitions,
                        controllers: _customFieldControllers,
                        selectValues: _customFieldSelectValues,
                        onSelectChanged: (fieldId, value) => setState(
                          () => _customFieldSelectValues[fieldId] = value,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Le date e gli assegnatari delle fasi li imposterai dopo, direttamente nel progetto.',
                      style: TextStyle(
                        fontSize: 12,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _createProject,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Crea progetto'),
                    style: FilledButton.styleFrom(
                      backgroundColor: GussoniBrand.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreationChoiceCard extends StatelessWidget {
  const _CreationChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.icon,
    required this.badge,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final IconData icon;
  final String badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? GussoniBrand.primaryBg : GussoniBrand.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? GussoniBrand.primary : GussoniBrand.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? GussoniBrand.primary.withValues(alpha: 0.12)
                    : GussoniBrand.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: selected
                    ? GussoniBrand.primary
                    : GussoniBrand.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: GussoniBrand.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: GussoniBrand.border),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: GussoniBrand.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: onTap == null ? null : (_) => onTap!(),
              activeColor: GussoniBrand.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GussoniBrand.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: GussoniBrand.textSecondary,
        ),
      ),
    );
  }
}
