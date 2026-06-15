import 'package:flutter/material.dart';

/// Comparsa morbida (fade + leggera risalita) con ritardo a cascata in base
/// all'indice. Implicita (nessun controller), si attiva al mount: per
/// rieseguirla cambiare la [key]. Rispetta `MediaQuery.disableAnimations`.
class GReveal extends StatelessWidget {
  const GReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.maxStagger = 12,
    this.baseMs = 280,
    this.stepMs = 38,
    this.dy = 10,
  });

  final Widget child;

  /// Posizione nella sequenza: determina il ritardo della cascata.
  final int index;

  /// Oltre questo indice il ritardo non cresce più (le code lunghe
  /// apparirebbero troppo tardi).
  final int maxStagger;

  final int baseMs;
  final int stepMs;
  final double dy;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return child;
    }
    final delayMs = index.clamp(0, maxStagger) * stepMs;
    final totalMs = baseMs + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(delayMs / totalMs, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, dy * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}
