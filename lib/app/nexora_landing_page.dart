import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class NexoraLandingPage extends StatefulWidget {
  const NexoraLandingPage({super.key, required this.onOpenApp});

  final VoidCallback onOpenApp;

  @override
  State<NexoraLandingPage> createState() => _NexoraLandingPageState();
}

class _NexoraLandingPageState extends State<NexoraLandingPage>
    with TickerProviderStateMixin {
  static const _scrollStep = 180.0;
  static const List<_LandingSection> _sections = [
    _LandingSection(
      label: 'Intro',
      title: 'Nexora',
      eyebrow: 'Operating workspace',
      headline: 'Il gestionale che si comporta come un sistema operativo.',
      body:
          'Un desktop vivo per tenere insieme vendita, operativita, tempo, note e decisioni. Nexora non ti porta dentro menu infiniti: apre contesti, li fa convivere e li lascia pronti quando torni.',
      icon: Icons.blur_on_rounded,
      accent: Color(0xFFD2B48C),
      mode: _PreviewMode.intro,
      chips: ['Desktop CRM', 'Finestre vive', 'Focus continuo'],
    ),
    _LandingSection(
      label: 'Vantaggi',
      title: 'Meno attrito',
      eyebrow: 'Perche funziona',
      headline: 'Un’interfaccia che riduce la fatica cognitiva.',
      body:
          'L’utente riconosce subito dove si trova: app, finestre, widget, dock, sessione. Il lavoro smette di sembrare una sequenza di schermate e diventa uno spazio operativo.',
      icon: Icons.auto_awesome_rounded,
      accent: Color(0xFFE8CFA8),
      mode: _PreviewMode.benefits,
      chips: ['Meno click', 'Piu memoria visiva', 'Adozione naturale'],
    ),
    _LandingSection(
      label: 'Funzioni',
      title: 'Stack OS',
      eyebrow: 'Cosa contiene',
      headline: 'CRM, planning e utility lavorano nello stesso ambiente.',
      body:
          'Societa, contatti, opportunita, task, calendario, memo, timer e finanze diventano app coordinate. Ogni elemento puo restare aperto, essere ripreso e dialogare con gli altri.',
      icon: Icons.widgets_rounded,
      accent: Color(0xFFD9A07C),
      mode: _PreviewMode.features,
      chips: ['CRM app', 'Widget desktop', 'Timer e calendario'],
    ),
    _LandingSection(
      label: 'Rivoluzione',
      title: 'Nuovo paradigma',
      eyebrow: 'Il salto',
      headline: 'Non e una dashboard piu bella. E un modo diverso di lavorare.',
      body:
          'La UX OS rende il software piu memorabile, piu proprietario, piu vendibile. Trasforma il gestionale in un prodotto con identita: riconoscibile, desiderabile, difficile da confondere.',
      icon: Icons.motion_photos_auto_rounded,
      accent: Color(0xFFE0A878),
      mode: _PreviewMode.revolution,
      chips: ['Brand experience', 'Prodotto memorabile', 'Effetto wow'],
    ),
    _LandingSection(
      label: 'Workflow',
      title: 'Flusso continuo',
      eyebrow: 'Come si usa',
      headline: 'Apri, affianchi, lavori, riprendi. Senza perdere il filo.',
      body:
          'Il desktop diventa la mappa della giornata: cio che serve resta visibile, cio che e finito si chiude, cio che e sospeso rimane in attesa. Come un computer, ma progettato per il business.',
      icon: Icons.account_tree_rounded,
      accent: Color(0xFFC9A36B),
      mode: _PreviewMode.workflow,
      chips: ['Sessione persistente', 'Gerarchie chiare', 'Lavoro ripreso'],
    ),
    _LandingSection(
      label: 'Contatto',
      title: 'Accendilo',
      eyebrow: 'Demo',
      headline: 'Vuoi vedere Nexora sul tuo modo reale di lavorare?',
      body:
          'Niente pricing generico: il valore nasce dal flusso. Scrivici, analizziamo il tuo processo e ti mostriamo come Nexora puo diventare il tuo sistema operativo operativo.',
      icon: Icons.mail_rounded,
      accent: Color(0xFFE3BE7A),
      mode: _PreviewMode.contact,
      chips: ['Demo guidata', 'Su misura', 'info@nexora.cloud'],
    ),
  ];

  late final AnimationController _ambientController;
  late final AnimationController _switchController;
  int _activeIndex = 0;
  int _previousIndex = 0;
  double _wheelAccumulator = 0;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _switchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..value = 1;
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _switchController.dispose();
    super.dispose();
  }

  void _activate(int index) {
    final next = index.clamp(0, _sections.length - 1);
    if (next == _activeIndex) {
      return;
    }
    setState(() {
      _previousIndex = _activeIndex;
      _activeIndex = next;
    });
    _switchController.forward(from: 0);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    _wheelAccumulator += event.scrollDelta.dy;
    if (_wheelAccumulator.abs() < _scrollStep) {
      return;
    }
    final direction = _wheelAccumulator.isNegative ? -1 : 1;
    _wheelAccumulator = 0;
    _activate(_activeIndex + direction);
  }

  Future<void> _contact() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'info@nexora.cloud',
      queryParameters: const {'subject': 'Richiesta informazioni Nexora'},
    );
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF240B04),
      body: Listener(
        onPointerSignal: _handlePointerSignal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            _wheelAccumulator -= details.delta.dy * 2.4;
            if (_wheelAccumulator.abs() < _scrollStep) {
              return;
            }
            final direction = _wheelAccumulator.isNegative ? -1 : 1;
            _wheelAccumulator = 0;
            _activate(_activeIndex + direction);
          },
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _ambientController,
              _switchController,
            ]),
            builder: (context, _) {
              return _LandingViewport(
                pulse: _ambientController.value,
                transition: Curves.easeOutCubic.transform(
                  _switchController.value,
                ),
                previous: _sections[_previousIndex],
                current: _sections[_activeIndex],
                sections: _sections,
                activeIndex: _activeIndex,
                onSectionTap: _activate,
                onOpenApp: widget.onOpenApp,
                onContact: _contact,
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _PreviewMode { intro, benefits, features, revolution, workflow, contact }

class _LandingSection {
  const _LandingSection({
    required this.label,
    required this.title,
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.icon,
    required this.accent,
    required this.mode,
    required this.chips,
  });

  final String label;
  final String title;
  final String eyebrow;
  final String headline;
  final String body;
  final IconData icon;
  final Color accent;
  final _PreviewMode mode;
  final List<String> chips;
}

class _LandingViewport extends StatelessWidget {
  const _LandingViewport({
    required this.pulse,
    required this.transition,
    required this.previous,
    required this.current,
    required this.sections,
    required this.activeIndex,
    required this.onSectionTap,
    required this.onOpenApp,
    required this.onContact,
  });

  final double pulse;
  final double transition;
  final _LandingSection previous;
  final _LandingSection current;
  final List<_LandingSection> sections;
  final int activeIndex;
  final ValueChanged<int> onSectionTap;
  final VoidCallback onOpenApp;
  final Future<void> Function() onContact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 760 || constraints.maxHeight < 680;
        final padding = compact ? 12.0 : 28.0;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _LandingWallpaperPainter(
                  pulse: pulse,
                  accent: current.accent,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1480),
                    child: _DesktopFrame(
                      compact: compact,
                      pulse: pulse,
                      transition: transition,
                      previous: previous,
                      current: current,
                      sections: sections,
                      activeIndex: activeIndex,
                      onSectionTap: onSectionTap,
                      onOpenApp: onOpenApp,
                      onContact: onContact,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopFrame extends StatelessWidget {
  const _DesktopFrame({
    required this.compact,
    required this.pulse,
    required this.transition,
    required this.previous,
    required this.current,
    required this.sections,
    required this.activeIndex,
    required this.onSectionTap,
    required this.onOpenApp,
    required this.onContact,
  });

  final bool compact;
  final double pulse;
  final double transition;
  final _LandingSection previous;
  final _LandingSection current;
  final List<_LandingSection> sections;
  final int activeIndex;
  final ValueChanged<int> onSectionTap;
  final VoidCallback onOpenApp;
  final Future<void> Function() onContact;

  @override
  Widget build(BuildContext context) {
    final flare = math.sin(transition * math.pi);
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 24 : 34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF331008).withValues(alpha: .78),
            borderRadius: BorderRadius.circular(compact ? 24 : 34),
            border: Border.all(color: Colors.white.withValues(alpha: .16)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 54,
                offset: Offset(0, 28),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 18),
            child: Column(
              children: [
                _DesktopChrome(
                  compact: compact,
                  onOpenApp: onOpenApp,
                  activeIndex: activeIndex,
                  total: sections.length,
                ),
                SizedBox(height: compact ? 10 : 16),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              compact ? 20 : 28,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF240B04),
                                const Color(0xFF42170B),
                                current.accent.withValues(alpha: .16),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _DesktopGridPainter(
                            pulse: pulse,
                            accent: current.accent,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 420),
                          opacity: .32 + flare * .22,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                compact ? 20 : 28,
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                                colors: [
                                  current.accent.withValues(alpha: .24),
                                  Colors.transparent,
                                  const Color(
                                    0xFF1F0A04,
                                  ).withValues(alpha: .42),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(compact ? 10 : 22),
                        child: _HeroWindowSwitcher(
                          compact: compact,
                          transition: transition,
                          previous: previous,
                          current: current,
                          onOpenApp: onOpenApp,
                          onContact: onContact,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 10 : 16),
                _SectionDock(
                  compact: compact,
                  sections: sections,
                  activeIndex: activeIndex,
                  onTap: onSectionTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopChrome extends StatelessWidget {
  const _DesktopChrome({
    required this.compact,
    required this.onOpenApp,
    required this.activeIndex,
    required this.total,
  });

  final bool compact;
  final VoidCallback onOpenApp;
  final int activeIndex;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 50 : 62,
      child: Row(
        children: [
          Container(
            height: compact ? 44 : 52,
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withValues(alpha: .08),
              border: Border.all(color: Colors.white.withValues(alpha: .13)),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/branding/app_icon.png',
                  width: compact ? 26 : 32,
                  height: compact ? 26 : 32,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Nexora',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.white.withValues(alpha: .16),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'OS workspace',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .58),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (!compact)
            Expanded(
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.white.withValues(alpha: .055),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .09),
                  ),
                ),
                child: Text(
                  'Sezione ${activeIndex + 1} di $total',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .58),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 14),
          FilledButton.icon(
            onPressed: onOpenApp,
            icon: const Icon(Icons.arrow_outward_rounded, size: 18),
            label: Text(compact ? 'Apri' : 'Apri dashboard'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD2B48C),
              foregroundColor: const Color(0xFF200A04),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 20,
                vertical: compact ? 13 : 17,
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroWindowSwitcher extends StatelessWidget {
  const _HeroWindowSwitcher({
    required this.compact,
    required this.transition,
    required this.previous,
    required this.current,
    required this.onOpenApp,
    required this.onContact,
  });

  final bool compact;
  final double transition;
  final _LandingSection previous;
  final _LandingSection current;
  final VoidCallback onOpenApp;
  final Future<void> Function() onContact;

  @override
  Widget build(BuildContext context) {
    final ignite = math.sin(transition * math.pi);
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (transition < 1)
          Transform.translate(
            offset: Offset(-90 * transition, 26 * transition),
            child: Opacity(
              opacity: (1 - transition).clamp(0, 1),
              child: Transform.scale(
                scale: 1 - transition * .08,
                child: _HeroWindow(
                  compact: compact,
                  section: previous,
                  muted: true,
                  onOpenApp: onOpenApp,
                  onContact: onContact,
                ),
              ),
            ),
          ),
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .001)
            ..rotateX((1 - transition) * .06)
            ..rotateY((1 - transition) * -.04),
          child: Transform.translate(
            offset: Offset((1 - transition) * 120, (1 - transition) * -18),
            child: Opacity(
              opacity: (.16 + transition * .84).clamp(0, 1),
              child: Transform.scale(
                scale: .92 + transition * .08 + ignite * .025,
                child: _HeroWindow(
                  compact: compact,
                  section: current,
                  muted: false,
                  onOpenApp: onOpenApp,
                  onContact: onContact,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroWindow extends StatelessWidget {
  const _HeroWindow({
    required this.compact,
    required this.section,
    required this.muted,
    required this.onOpenApp,
    required this.onContact,
  });

  final bool compact;
  final _LandingSection section;
  final bool muted;
  final VoidCallback onOpenApp;
  final Future<void> Function() onContact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? 860 : 1180,
          maxHeight: compact ? 720 : 760,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 24 : 32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(
                  0xFFFCF8F2,
                ).withValues(alpha: muted ? .74 : .94),
                borderRadius: BorderRadius.circular(compact ? 24 : 32),
                border: Border.all(color: Colors.white.withValues(alpha: .42)),
                boxShadow: [
                  BoxShadow(
                    color: section.accent.withValues(alpha: muted ? .08 : .22),
                    blurRadius: muted ? 18 : 40,
                    offset: const Offset(0, 22),
                  ),
                  const BoxShadow(
                    color: Color(0x4A000000),
                    blurRadius: 38,
                    offset: Offset(0, 24),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _WindowHeader(section: section, compact: compact),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 18 : 30),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final stackBody = constraints.maxWidth < 820;
                          if (stackBody) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _HeroCopy(
                                  compact: true,
                                  section: section,
                                  onOpenApp: onOpenApp,
                                  onContact: onContact,
                                ),
                                const SizedBox(height: 18),
                                Expanded(
                                  child: _PreviewSurface(section: section),
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                flex: 11,
                                child: _HeroCopy(
                                  compact: false,
                                  section: section,
                                  onOpenApp: onOpenApp,
                                  onContact: onContact,
                                ),
                              ),
                              const SizedBox(width: 28),
                              Expanded(
                                flex: 10,
                                child: _PreviewSurface(section: section),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowHeader extends StatelessWidget {
  const _WindowHeader({required this.section, required this.compact});

  final _LandingSection section;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 58 : 68,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: .84),
            section.accent.withValues(alpha: .12),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: section.accent.withValues(alpha: .18)),
        ),
      ),
      child: Row(
        children: [
          _NexoraWindowControls(accent: section.accent),
          SizedBox(width: compact ? 10 : 14),
          Container(
            width: compact ? 34 : 40,
            height: compact ? 34 : 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  section.accent.withValues(alpha: .96),
                  const Color(0xFF200A04),
                ],
              ),
            ),
            child: Icon(
              section.icon,
              color: Colors.white,
              size: compact ? 17 : 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              section.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF2B0D05),
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (!compact)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withValues(alpha: .62),
                border: Border.all(
                  color: section.accent.withValues(alpha: .18),
                ),
              ),
              child: Text(
                section.eyebrow,
                style: TextStyle(
                  color: section.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NexoraWindowControls extends StatelessWidget {
  const _NexoraWindowControls({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFF240B04).withValues(alpha: .08),
        border: Border.all(
          color: const Color(0xFF240B04).withValues(alpha: .07),
        ),
      ),
      child: Row(
        children: List.generate(3, (index) {
          return Container(
            width: 13,
            height: 13,
            margin: EdgeInsets.only(right: index == 2 ? 0 : 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: Color.lerp(accent, const Color(0xFF240B04), index * .18),
            ),
          );
        }),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.compact,
    required this.section,
    required this.onOpenApp,
    required this.onContact,
  });

  final bool compact;
  final _LandingSection section;
  final VoidCallback onOpenApp;
  final Future<void> Function() onContact;

  @override
  Widget build(BuildContext context) {
    final isContact = section.mode == _PreviewMode.contact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: section.accent.withValues(alpha: .13),
            border: Border.all(color: section.accent.withValues(alpha: .22)),
          ),
          child: Text(
            section.eyebrow.toUpperCase(),
            style: TextStyle(
              color: Color.lerp(section.accent, const Color(0xFF200A04), .24),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        SizedBox(height: compact ? 14 : 20),
        Text(
          section.headline,
          style: TextStyle(
            color: const Color(0xFF200A04),
            fontSize: compact ? 34 : 52,
            height: .98,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: compact ? 14 : 20),
        Text(
          section.body,
          style: TextStyle(
            color: const Color(0xFF7A4A33),
            fontSize: compact ? 15 : 18,
            height: 1.42,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: compact ? 16 : 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: section.chips
              .map((chip) => _LandingChip(label: chip, accent: section.accent))
              .toList(),
        ),
        SizedBox(height: compact ? 16 : 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: isContact ? onContact : onOpenApp,
              icon: Icon(
                isContact ? Icons.mail_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(
                isContact ? 'Scrivi a info@nexora.cloud' : 'Apri dashboard',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF200A04),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 17,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onContact,
              icon: const Icon(Icons.alternate_email_rounded),
              label: const Text('Contattaci'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF200A04),
                side: BorderSide(color: section.accent.withValues(alpha: .46)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 17,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LandingChip extends StatelessWidget {
  const _LandingChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: .72),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF4F1E0E),
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({required this.section});

  final _LandingSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF240B04),
            const Color(0xFF42170B),
            section.accent.withValues(alpha: .20),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .15)),
        boxShadow: [
          BoxShadow(
            color: section.accent.withValues(alpha: .16),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CustomPaint(
          painter: _PreviewPatternPainter(accent: section.accent),
          child: switch (section.mode) {
            _PreviewMode.intro => _IntroPreview(accent: section.accent),
            _PreviewMode.benefits => _BenefitsPreview(accent: section.accent),
            _PreviewMode.features => _FeaturesPreview(accent: section.accent),
            _PreviewMode.revolution => _RevolutionPreview(
              accent: section.accent,
            ),
            _PreviewMode.workflow => _WorkflowPreview(accent: section.accent),
            _PreviewMode.contact => _ContactPreview(
              accent: section.accent,
              onContact: () => onContactSafe(context),
            ),
          },
        ),
      ),
    );
  }

  Future<void> onContactSafe(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'info@nexora.cloud',
      queryParameters: const {'subject': 'Richiesta informazioni Nexora'},
    );
    await launchUrl(uri);
  }
}

class _IntroPreview extends StatelessWidget {
  const _IntroPreview({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _PreviewWindowTile(
                    accent: accent,
                    icon: Icons.business_rounded,
                    title: 'Societa',
                    lines: const [86, 130, 112],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _PreviewWindowTile(
                    accent: const Color(0xFFE8CFA8),
                    icon: Icons.calendar_month_rounded,
                    title: 'Planning',
                    lines: const [118, 92, 136],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _PreviewWindowTile(
                    accent: const Color(0xFFE0A878),
                    icon: Icons.timer_rounded,
                    title: 'Timer',
                    lines: const [92, 120, 72],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _PreviewWindowTile(
                    accent: const Color(0xFFD9A07C),
                    icon: Icons.sticky_note_2_rounded,
                    title: 'Memo',
                    lines: const [126, 82, 104],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitsPreview extends StatelessWidget {
  const _BenefitsPreview({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              _MetricCard(accent: accent, value: '-38%', label: 'attrito'),
              const SizedBox(width: 12),
              _MetricCard(accent: accent, value: '+2.4x', label: 'focus'),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(5, (index) {
                final height = 44.0 + index * 24;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: index == 4 ? 0 : 10),
                    height: height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          accent.withValues(alpha: .30),
                          accent.withValues(alpha: .86),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturesPreview extends StatelessWidget {
  const _FeaturesPreview({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    const labels = [
      'CRM app',
      'Calendario',
      'Memo',
      'Timer',
      'Finanze',
      'Widget',
    ];
    return Padding(
      padding: const EdgeInsets.all(18),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.15,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: labels.length,
        itemBuilder: (context, index) {
          return _FeatureTile(
            label: labels[index],
            icon: [
              Icons.folder_special_rounded,
              Icons.event_available_rounded,
              Icons.speaker_notes_rounded,
              Icons.timer_rounded,
              Icons.account_balance_wallet_rounded,
              Icons.dashboard_customize_rounded,
            ][index],
            accent: index.isEven ? accent : const Color(0xFFD2B48C),
          );
        },
      ),
    );
  }
}

class _RevolutionPreview extends StatelessWidget {
  const _RevolutionPreview({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: const [
          _StatementRow(
            number: '01',
            text: 'Il prodotto diventa riconoscibile',
          ),
          SizedBox(height: 12),
          _StatementRow(
            number: '02',
            text: 'La UX comunica valore prima della demo',
          ),
          SizedBox(height: 12),
          _StatementRow(
            number: '03',
            text: 'Il team lavora in uno spazio mentale unico',
          ),
        ],
      ),
    );
  }
}

class _WorkflowPreview extends StatelessWidget {
  const _WorkflowPreview({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Apri', Icons.open_in_new_rounded),
      ('Affianchi', Icons.view_quilt_rounded),
      ('Esegui', Icons.task_alt_rounded),
      ('Riprendi', Icons.history_rounded),
    ];
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(steps.length, (index) {
          final step = steps[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == steps.length - 1 ? 0 : 14,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: accent.withValues(alpha: .20),
                    border: Border.all(color: accent.withValues(alpha: .28)),
                  ),
                  child: Icon(step.$2, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    height: 44,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withValues(alpha: .10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .11),
                      ),
                    ),
                    child: Text(
                      step.$1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _ContactPreview extends StatelessWidget {
  const _ContactPreview({required this.accent, required this.onContact});

  final Color accent;
  final Future<void> Function() onContact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 250;
        return Padding(
          padding: EdgeInsets.all(tight ? 12 : 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mark_email_unread_rounded,
                color: accent,
                size: tight ? 46 : 62,
              ),
              SizedBox(height: tight ? 10 : 14),
              Text(
                'info@nexora.cloud',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: tight ? 22 : 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: tight ? 7 : 10),
              Text(
                'Scrivici per una demo costruita sul tuo workflow.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .68),
                  fontSize: tight ? 13 : 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: tight ? 12 : 18),
              FilledButton.icon(
                onPressed: onContact,
                icon: const Icon(Icons.mail_rounded, size: 18),
                label: const Text('Contatta Nexora'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF200A04),
                  padding: EdgeInsets.symmetric(
                    horizontal: tight ? 16 : 20,
                    vertical: tight ? 12 : 15,
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewWindowTile extends StatelessWidget {
  const _PreviewWindowTile({
    required this.accent,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final List<double> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: .12),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: accent.withValues(alpha: .20),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          ...lines.map(
            (width) => Container(
              width: width,
              height: 8,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withValues(alpha: .22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.accent,
    required this.value,
    required this.label,
  });

  final Color accent;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withValues(alpha: .12),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .70),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: .12),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: accent.withValues(alpha: .22),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementRow extends StatelessWidget {
  const _StatementRow({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withValues(alpha: .12),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(
          children: [
            Text(
              number,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .36),
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionDock extends StatelessWidget {
  const _SectionDock({
    required this.compact,
    required this.sections,
    required this.activeIndex,
    required this.onTap,
  });

  final bool compact;
  final List<_LandingSection> sections;
  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 74 : 92,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        color: Colors.white.withValues(alpha: .095),
        border: Border.all(color: Colors.white.withValues(alpha: .13)),
      ),
      child: Row(
        children: List.generate(sections.length, (index) {
          final section = sections[index];
          final active = index == activeIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 5),
              child: Tooltip(
                message: section.label,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(compact ? 18 : 22),
                    onTap: () => onTap(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 10,
                        vertical: compact ? 6 : 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(compact ? 18 : 22),
                        color: active
                            ? section.accent.withValues(alpha: .18)
                            : Colors.white.withValues(alpha: .06),
                        border: Border.all(
                          color: active
                              ? section.accent.withValues(alpha: .42)
                              : Colors.white.withValues(alpha: .08),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            section.icon,
                            color: Colors.white,
                            size: compact ? 18 : 24,
                          ),
                          SizedBox(height: compact ? 4 : 7),
                          Flexible(
                            child: Text(
                              compact ? '${index + 1}' : section.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(
                                  alpha: active ? .98 : .68,
                                ),
                                fontSize: compact ? 10 : 12,
                                fontWeight: FontWeight.w900,
                              ),
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
        }),
      ),
    );
  }
}

class _LandingWallpaperPainter extends CustomPainter {
  const _LandingWallpaperPainter({required this.pulse, required this.accent});

  final double pulse;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F0A04), Color(0xFF3B1409), Color(0xFF240B04)],
        ).createShader(rect),
    );

    final bandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: .20),
          Colors.transparent,
          const Color(0xFFE8CFA8).withValues(alpha: .10),
        ],
      ).createShader(rect);

    final path = Path()
      ..moveTo(size.width * -.10, size.height * (.28 + pulse * .04))
      ..cubicTo(
        size.width * .25,
        size.height * .02,
        size.width * .52,
        size.height * .70,
        size.width * 1.12,
        size.height * (.22 + pulse * .05),
      )
      ..lineTo(size.width * 1.12, size.height * (.48 + pulse * .04))
      ..cubicTo(
        size.width * .54,
        size.height * .86,
        size.width * .24,
        size.height * .20,
        size.width * -.10,
        size.height * .54,
      )
      ..close();
    canvas.drawPath(path, bandPaint);
  }

  @override
  bool shouldRepaint(covariant _LandingWallpaperPainter oldDelegate) {
    return oldDelegate.pulse != pulse || oldDelegate.accent != accent;
  }
}

class _DesktopGridPainter extends CustomPainter {
  const _DesktopGridPainter({required this.pulse, required this.accent});

  final double pulse;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .055)
      ..strokeWidth = 1;
    const step = 54.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final sweep = Paint()
      ..shader =
          LinearGradient(
            colors: [
              Colors.transparent,
              accent.withValues(alpha: .16),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromLTWH(
              size.width * (pulse - .38),
              0,
              size.width * .76,
              size.height,
            ),
          );
    canvas.drawRect(Offset.zero & size, sweep);
  }

  @override
  bool shouldRepaint(covariant _DesktopGridPainter oldDelegate) {
    return oldDelegate.pulse != pulse || oldDelegate.accent != accent;
  }
}

class _PreviewPatternPainter extends CustomPainter {
  const _PreviewPatternPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: .045)
      ..strokeWidth = 1;
    for (var i = 0; i < 9; i++) {
      final y = size.height * i / 8;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    final accentPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent.withValues(alpha: .18), Colors.transparent],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _PreviewPatternPainter oldDelegate) {
    return oldDelegate.accent != accent;
  }
}
