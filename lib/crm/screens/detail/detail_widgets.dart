import 'package:flutter/material.dart';
import '../../../brand_config.dart';

// ────────────────────────────────────────────────
// Widget condivisi per le schede dettaglio
// ────────────────────────────────────────────────

// ── Back bar ──

class DetailBackBar extends StatelessWidget {
  const DetailBackBar({
    super.key,
    required this.label,
    required this.onBack,
    this.actions = const [],
  });

  final String label;
  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: GussoniBrand.glassField(radius: 999),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: GussoniBrand.textMuted,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

// ── Info card ──

class DetailInfoCard extends StatefulWidget {
  const DetailInfoCard({
    super.key,
    required this.title,
    required this.rows,
    this.avatar,
    this.tags = const [],
    this.onEdit,
  });

  final String title;
  final List<DetailInfoRow> rows;
  final Widget? avatar;
  final List<String> tags;
  final VoidCallback? onEdit;

  @override
  State<DetailInfoCard> createState() => _DetailInfoCardState();
}

class _DetailInfoCardState extends State<DetailInfoCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: GussoniBrand.glassPanel(
        radius: 22,
        accent: GussoniBrand.surface,
        opacity: .98,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: GussoniBrand.textPrimary,
                ),
              ),
              const Spacer(),
              if (widget.onEdit != null)
                IconButton(
                  onPressed: widget.onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 17,
                    color: GussoniBrand.textMuted,
                  ),
                  tooltip: 'Modifica',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.avatar != null) ...[
            widget.avatar!,
            const SizedBox(height: 16),
          ],
          if (widget.tags.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.tags.map((t) => _Tag(label: t)).toList(),
            ),
            const SizedBox(height: 14),
          ],
          ...widget.rows.map((row) => _InfoRow(row: row)),
        ],
      ),
    );
  }
}

class DetailInfoRow {
  const DetailInfoRow({
    required this.label,
    required this.value,
    this.isLink = false,
    this.icon,
  });
  final String label;
  final String value;
  final bool isLink;
  final IconData? icon;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.row});
  final DetailInfoRow row;

  @override
  Widget build(BuildContext context) {
    if (row.value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              row.label,
              style: const TextStyle(
                fontSize: 13,
                color: GussoniBrand.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.value,
              style: TextStyle(
                fontSize: 13,
                color: row.isLink
                    ? GussoniBrand.primary
                    : GussoniBrand.textPrimary,
                fontWeight: FontWeight.w500,
                decoration: row.isLink ? TextDecoration.underline : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: GussoniBrand.surfaceSubtle,
      border: Border.all(color: GussoniBrand.border),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: GussoniBrand.textSecondary,
      ),
    ),
  );
}

// ── Notes card ──

class DetailNotesCard extends StatefulWidget {
  const DetailNotesCard({super.key, required this.notes, required this.onSave});
  final String notes;
  final Future<void> Function(String) onSave;
  @override
  State<DetailNotesCard> createState() => _DetailNotesCardState();
}

class _DetailNotesCardState extends State<DetailNotesCard> {
  bool _editing = false;
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.notes);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: GussoniBrand.glassPanel(
        radius: 22,
        accent: GussoniBrand.surface,
        opacity: .98,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Considerazioni',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: GussoniBrand.textPrimary,
                ),
              ),
              const Spacer(),
              if (!_editing)
                IconButton(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 17,
                    color: GussoniBrand.textMuted,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_editing) ...[
            TextField(
              controller: _ctrl,
              maxLines: 6,
              autofocus: true,
              style: const TextStyle(color: GussoniBrand.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Aggiungi note interne...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _ctrl.text = widget.notes;
                    _editing = false;
                  }),
                  child: const Text('Annulla'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          await widget.onSave(_ctrl.text.trim());
                          if (mounted)
                            setState(() {
                              _saving = false;
                              _editing = false;
                            });
                        },
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salva'),
                ),
              ],
            ),
          ] else ...[
            if (widget.notes.isEmpty)
              const Text(
                'Nessuna nota.',
                style: TextStyle(
                  fontSize: 13,
                  color: GussoniBrand.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Text(
                widget.notes,
                style: const TextStyle(
                  fontSize: 13,
                  color: GussoniBrand.textSecondary,
                  height: 1.5,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Accordion section ──

class DetailAccordion extends StatefulWidget {
  const DetailAccordion({
    super.key,
    required this.title,
    required this.count,
    required this.children,
    this.initiallyExpanded = false,
    this.onAdd,
  });

  final String title;
  final int count;
  final List<Widget> children;
  final bool initiallyExpanded;
  final VoidCallback? onAdd;

  @override
  State<DetailAccordion> createState() => _DetailAccordionState();
}

class _DetailAccordionState extends State<DetailAccordion>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController _anim;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: _expanded ? 1 : 0,
    );
    _rotation = Tween<double>(
      begin: 0,
      end: 0.25,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: GussoniBrand.glassPanel(
        radius: 18,
        accent: GussoniBrand.surface,
        opacity: .98,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(18))
                : BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  RotationTransition(
                    turns: _rotation,
                    child: const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: GussoniBrand.surfaceSubtle,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.onAdd != null)
                    IconButton(
                      onPressed: widget.onAdd,
                      icon: const Icon(
                        Icons.add,
                        size: 18,
                        color: GussoniBrand.textMuted,
                      ),
                      tooltip: 'Aggiungi',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: 1),
                if (widget.children.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nessun elemento collegato.',
                      style: TextStyle(
                        fontSize: 13,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  )
                else
                  ...widget.children,
              ],
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

// ── Accordion row item ──

class AccordionRow extends StatelessWidget {
  const AccordionRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.badge,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            leading,
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
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: GussoniBrand.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[const SizedBox(width: 8), badge!],
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: GussoniBrand.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: GussoniBrand.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Divider between accordion rows ──

class AccordionDivider extends StatelessWidget {
  const AccordionDivider({super.key});
  @override
  Widget build(BuildContext context) => const Divider(
    height: 1,
    color: GussoniBrand.borderSubtle,
    indent: 16,
    endIndent: 16,
  );
}

// ── Status badge ──

class DetailBadge extends StatelessWidget {
  const DetailBadge({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: color.withValues(alpha: 0.10),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

// ── Entity icon avatar ──

class EntityAvatar extends StatelessWidget {
  const EntityAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.size = 48,
  });
  final String initials;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.15),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.33,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ),
  );
}

Color colorForName(String name) {
  final base = GussoniBrand.primary;
  final hsl = HSLColor.fromColor(base);
  final hash = name.codeUnits.fold<int>(0, (a, c) => a * 31 + c).abs();
  final lightnessOffset = ((hash % 5) - 2) * 0.06;
  final satOffset = ((hash % 3) - 1) * 0.08;
  return hsl
      .withLightness((hsl.lightness + lightnessOffset).clamp(0.25, 0.65))
      .withSaturation((hsl.saturation + satOffset).clamp(0.3, 1.0))
      .toColor();
}

String initialsFor(String name) {
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}
