import 'package:flutter/material.dart';

import '../brand_config.dart';

/// Dialog OS-style che replica l'aspetto dei DesktopWindow (glass opaco, titlebar, ombra).
/// Usato al posto di AlertDialog in tutta l'app.
class NexoraDialog extends StatelessWidget {
  const NexoraDialog({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.accent,
    this.actions = const [],
    this.width = 520,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Color? accent;
  final List<Widget> actions;
  final double width;

  /// Decorazione standard per i campi form nei dialog.
  static InputDecoration fieldDecoration(
    String label, {
    String? hint,
    String? prefix,
    String? suffix,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      suffixText: suffix,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: GussoniBrand.scaffoldBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: GussoniBrand.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: GussoniBrand.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: GussoniBrand.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: GussoniBrand.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: GussoniBrand.error, width: 1.4),
      ),
      labelStyle: const TextStyle(color: GussoniBrand.textMuted, fontSize: 13),
      hintStyle: const TextStyle(color: GussoniBrand.textMuted, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final eff = accent ?? GussoniBrand.primary;
    final media = MediaQuery.of(context);
    final compact = media.size.width < 760;
    if (compact) {
      return _NexoraMobileSheet(
        title: title,
        icon: icon,
        accent: eff,
        actions: actions,
        child: child,
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
      child: _DialogEntrance(
        child: Container(
          width: width,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: GussoniBrand.surface,
            border: Border.all(color: GussoniBrand.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Titlebar ────────────────────────────────────────────
                Container(
                  height: 60,
                  padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
                  decoration: const BoxDecoration(
                    color: GussoniBrand.surface,
                    border: Border(
                      bottom: BorderSide(color: GussoniBrand.borderSubtle),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: eff.withValues(alpha: .10),
                          ),
                          child: Icon(icon, color: eff, size: 18),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: GussoniBrand.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _NexoraCloseButton(
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // ── Content ─────────────────────────────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                    child: child,
                  ),
                ),

                // ── Actions ─────────────────────────────────────────────
                if (actions.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: GussoniBrand.borderSubtle),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (int i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          actions[i],
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Stile standard per il bottone primario nei dialog.
  static ButtonStyle primaryButtonStyle({Color? color}) =>
      FilledButton.styleFrom(
        backgroundColor: color ?? GussoniBrand.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      );

  /// Stile standard per il bottone annulla nei dialog.
  static ButtonStyle cancelButtonStyle() => TextButton.styleFrom(
    foregroundColor: GussoniBrand.textMuted,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

/// Frame adattivo per form complessi: finestra glass su desktop, sheet iPhone-like su mobile.
class NexoraAdaptiveDialogFrame extends StatelessWidget {
  const NexoraAdaptiveDialogFrame({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.accent,
    this.width = 760,
    this.maxHeightFactor = .92,
    this.contentPadding,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Color? accent;
  final double width;
  final double maxHeightFactor;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final eff = accent ?? GussoniBrand.primary;
    final compact = media.size.width < 760;
    if (compact) {
      return _NexoraMobileSheet(
        title: title,
        icon: icon,
        accent: eff,
        contentPadding: contentPadding ?? EdgeInsets.zero,
        child: child,
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      child: _DialogEntrance(
        child: Container(
          width: width,
          constraints: BoxConstraints(
            maxHeight: media.size.height * maxHeightFactor,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: GussoniBrand.surface,
            border: Border.all(color: GussoniBrand.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _NexoraMobileSheet extends StatelessWidget {
  const _NexoraMobileSheet({
    required this.title,
    required this.child,
    required this.accent,
    this.icon,
    this.actions = const [],
    this.contentPadding,
  });

  final String title;
  final Widget child;
  final Color accent;
  final IconData? icon;
  final List<Widget> actions;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = media.viewInsets.bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottom),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            child: _DialogEntrance(
              dy: 28,
              scaleFrom: 1,
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: media.size.height * (bottom > 0 ? .96 : .92),
                ),
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                    bottom: Radius.circular(16),
                  ),
                  color: GussoniBrand.surface,
                  border: Border.all(color: GussoniBrand.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x42000000),
                      blurRadius: 30,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8EA3B7).withValues(alpha: .42),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Container(
                      height: 58,
                      padding: const EdgeInsets.fromLTRB(16, 8, 10, 10),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: GussoniBrand.borderSubtle),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (icon != null) ...[
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: accent.withValues(alpha: .10),
                              ),
                              child: Icon(icon, color: accent, size: 18),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: GussoniBrand.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            style: TextButton.styleFrom(
                              foregroundColor: accent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            child: const Text('Fine'),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding:
                            contentPadding ??
                            const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: child,
                      ),
                    ),
                    if (actions.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: GussoniBrand.borderSubtle),
                          ),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 10,
                          runSpacing: 8,
                          children: actions,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Dialog di conferma OS-style (si, no / azione pericolosa).
class NexoraConfirmDialog extends StatelessWidget {
  const NexoraConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.accent,
    this.confirmLabel = 'Conferma',
    this.cancelLabel = 'Annulla',
    this.isDanger = false,
    this.detail,
  });

  final String title;
  final String message;
  final Widget? detail;
  final IconData? icon;
  final Color? accent;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final confirmColor = isDanger
        ? GussoniBrand.error
        : (accent ?? GussoniBrand.primary);
    return NexoraDialog(
      title: title,
      icon:
          icon ??
          (isDanger ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
      accent: confirmColor,
      width: 440,
      // ignore: sort_child_properties_last
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              color: GussoniBrand.textSecondary,
            ),
          ),
          if (detail != null) ...[const SizedBox(height: 14), detail!],
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: NexoraDialog.cancelButtonStyle(),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: NexoraDialog.primaryButtonStyle(color: confirmColor),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Dialog di input testo OS-style.
class NexoraInputDialog extends StatefulWidget {
  const NexoraInputDialog({
    super.key,
    required this.title,
    required this.label,
    this.initialValue = '',
    this.icon,
    this.accent,
    this.confirmLabel = 'Salva',
    this.cancelLabel = 'Annulla',
    this.maxLines = 1,
    this.autofocus = true,
    this.width = 440,
  });

  final String title;
  final String label;
  final String initialValue;
  final IconData? icon;
  final Color? accent;
  final String confirmLabel;
  final String cancelLabel;
  final int maxLines;
  final bool autofocus;
  final double width;

  @override
  State<NexoraInputDialog> createState() => _NexoraInputDialogState();
}

class _NexoraInputDialogState extends State<NexoraInputDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NexoraDialog(
      title: widget.title,
      icon: widget.icon,
      accent: widget.accent,
      width: widget.width,
      // ignore: sort_child_properties_last
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: TextField(
          controller: _ctrl,
          autofocus: widget.autofocus,
          maxLines: widget.maxLines,
          decoration: NexoraDialog.fieldDecoration(widget.label),
          onSubmitted: widget.maxLines == 1
              ? (v) => Navigator.of(context).pop(v.trim())
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: NexoraDialog.cancelButtonStyle(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          style: NexoraDialog.primaryButtonStyle(color: widget.accent),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Bottone X per chiudere il dialog (titlebar).
class _NexoraCloseButton extends StatelessWidget {
  const _NexoraCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: GussoniBrand.surfaceSubtle,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.close_rounded,
          size: 16,
          color: GussoniBrand.textSecondary,
        ),
      ),
    );
  }
}

/// Ingresso morbido per i dialog: scale+fade (desktop) o slide-up (sheet).
class _DialogEntrance extends StatelessWidget {
  const _DialogEntrance({
    required this.child,
    this.dy = 8,
    this.scaleFrom = .96,
  });

  final Widget child;
  final double dy;
  final double scaleFrom;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, dy * (1 - t)),
          child: Transform.scale(
            scale: scaleFrom + (1 - scaleFrom) * t,
            child: child,
          ),
        ),
      ),
    );
  }
}
