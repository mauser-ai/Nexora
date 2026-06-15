import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'desktop_shell.dart';

abstract class _IosNexora {
  static const ink = Color(0xFFFCFAF7);
  static const muted = Color(0xB8F7FBFF);
  static const line = Color(0x30FFFFFF);
  static const dark = Color(0xFF200A04);
  static const teal = Color(0xFF5B1205);
  static const cyan = Color(0xFFD2B48C);

  static BoxDecoration surface({
    double radius = 28,
    Color? accent,
    double opacity = .30,
  }) {
    final glow = accent ?? teal;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: opacity + .08),
          const Color(0xFF4F1E0E).withValues(alpha: opacity),
          glow.withValues(alpha: .12),
        ],
      ),
      border: Border.all(color: line),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .24),
          blurRadius: 24,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IosShellScaffold
//
// Architettura a Stack — il wallpaper è SEMPRE presente alla base.
// Home screen e pannello app sono livelli animati sopra.
// L'app si apre come un glass panel che sale dal basso (non Navigator.push),
// quindi il wallpaper rimane visibile attraverso l'effetto glass.
// ─────────────────────────────────────────────────────────────────────────────

class IosShellScaffold extends StatefulWidget {
  const IosShellScaffold({
    super.key,
    required this.apps,
    required this.userLabel,
    required this.onLogout,
    this.wallpaperUrl,
    this.dockAppIds,
    this.controller,
    this.isTablet = false,
  });

  final List<DesktopShellApp> apps;
  final String userLabel;
  final VoidCallback onLogout;
  final String? wallpaperUrl;
  final List<String>? dockAppIds;
  final DesktopShellController? controller;
  final bool isTablet;

  @override
  State<IosShellScaffold> createState() => _IosShellScaffoldState();
}

class _IosShellScaffoldState extends State<IosShellScaffold>
    with TickerProviderStateMixin {
  // ── Navigation state ─────────────────────────────────────────────────────────
  DesktopShellApp? _openApp;

  late final AnimationController _transCtrl;
  late final Animation<double> _homeFadeAnim;
  late final Animation<Offset> _panelSlideAnim;
  late final Animation<double> _panelFadeAnim;

  // ── Home paging ──────────────────────────────────────────────────────────────
  final _pageCtrl = PageController();
  int _currentPage = 0;
  String _query = '';

  // ── Clock ────────────────────────────────────────────────────────────────────
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // ── Grid ─────────────────────────────────────────────────────────────────────
  int get _columns => widget.isTablet ? 5 : 4;
  int get _dockMax => widget.isTablet ? 5 : 4;

  List<DesktopShellApp> get _dockApps {
    final ids = widget.dockAppIds;
    if (ids != null && ids.isNotEmpty) {
      return ids
          .map((id) => widget.apps.where((a) => a.id == id).firstOrNull)
          .whereType<DesktopShellApp>()
          .take(_dockMax)
          .toList();
    }
    final shortcuts = widget.apps.where((a) => a.desktopShortcut).toList();
    return (shortcuts.isNotEmpty ? shortcuts : widget.apps)
        .take(_dockMax)
        .toList();
  }

  List<List<DesktopShellApp>> _computePages(
    int appsPerPage,
    List<DesktopShellApp> apps,
  ) {
    final pages = <List<DesktopShellApp>>[];
    for (var i = 0; i < apps.length; i += appsPerPage) {
      pages.add(apps.sublist(i, min(i + appsPerPage, apps.length)));
    }
    if (pages.isEmpty) pages.add(const []);
    return pages;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _transCtrl = AnimationController(
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 240),
      vsync: this,
    );
    _homeFadeAnim = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _transCtrl, curve: const Interval(0, 0.5)),
    );
    _panelSlideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _transCtrl, curve: Curves.easeOutCubic));
    _panelFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _transCtrl, curve: const Interval(0, 0.6)),
    );

    widget.controller?.addListener(_handleController);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant IosShellScaffold old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_handleController);
      widget.controller?.addListener(_handleController);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleController);
    _transCtrl.dispose();
    _pageCtrl.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _handleController() {}

  // ── App open / close ──────────────────────────────────────────────────────────

  Future<void> _openAppScreen(DesktopShellApp app) async {
    HapticFeedback.lightImpact();
    setState(() => _openApp = app);
    await _transCtrl.forward();
  }

  Future<void> _closeAppScreen() async {
    HapticFeedback.lightImpact();
    await _transCtrl.reverse();
    if (mounted) setState(() => _openApp = null);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final topPad = media.padding.top;
        final bottomPad = media.padding.bottom;

        // Calcolo righe disponibili
        final statusH = widget.isTablet ? 166.0 : 148.0;
        final dockH = widget.isTablet ? 118.0 : 108.0;
        const dotsH = 28.0;
        const vPad = 24.0;

        final iconSize = widget.isTablet ? 74.0 : 62.0;
        final cellH = iconSize + 38.0;
        final gridH =
            constraints.maxHeight -
            topPad -
            statusH -
            dotsH -
            dockH -
            bottomPad -
            vPad;
        final rows = (gridH / cellH).floor().clamp(2, 8);
        final appsPerPage = _columns * rows;
        final normalizedQuery = _query.trim().toLowerCase();
        final visibleApps = normalizedQuery.isEmpty
            ? widget.apps
            : widget.apps
                  .where(
                    (app) =>
                        app.title.toLowerCase().contains(normalizedQuery) ||
                        app.subtitle.toLowerCase().contains(normalizedQuery),
                  )
                  .toList();
        final pages = _computePages(appsPerPage, visibleApps);
        final safeCurrentPage = _currentPage.clamp(0, pages.length - 1);

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── Layer 0: Wallpaper (sempre visibile) ──────────────────────────
              _IosWallpaper(url: widget.wallpaperUrl),

              // ── Layer 1: Overlay scuro per leggibilità ────────────────────────
              const _IosAtmosphere(),

              // ── Layer 2: Home screen (evanisce quando app si apre) ────────────
              FadeTransition(
                opacity: _homeFadeAnim,
                child: SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      _IosStatusBar(
                        now: _now,
                        userLabel: widget.userLabel,
                        onLogout: widget.onLogout,
                      ),
                      _IosWorkspaceHeader(
                        userLabel: widget.userLabel,
                        page: safeCurrentPage,
                        pages: pages.length,
                        query: _query,
                        onQueryChanged: (value) => setState(() {
                          _query = value;
                          _currentPage = 0;
                          if (_pageCtrl.hasClients) {
                            _pageCtrl.jumpToPage(0);
                          }
                        }),
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _pageCtrl,
                          onPageChanged: (i) =>
                              setState(() => _currentPage = i),
                          itemCount: pages.length,
                          itemBuilder: (_, pi) => _IosHomePage(
                            apps: pages[pi],
                            columns: _columns,
                            iconSize: iconSize,
                            onTap: _openAppScreen,
                          ),
                        ),
                      ),
                      _IosPageDots(
                        count: pages.length,
                        current: safeCurrentPage,
                      ),
                      const SizedBox(height: 4),
                      _IosDock(
                        apps: _dockApps,
                        iconSize: widget.isTablet ? 64.0 : 56.0,
                        onTap: _openAppScreen,
                      ),
                      SizedBox(height: bottomPad > 0 ? 0 : 12),
                    ],
                  ),
                ),
              ),

              // ── Layer 3: App full-screen (stile iPhone) ─────────────────────
              if (_openApp != null)
                SlideTransition(
                  position: _panelSlideAnim,
                  child: FadeTransition(
                    opacity: _panelFadeAnim,
                    child: _IosAppPanel(
                      app: _openApp!,
                      topPad: topPad,
                      bottomPad: bottomPad,
                      onClose: _closeAppScreen,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass app panel — stile identico ai DesktopWindow attivi
// ─────────────────────────────────────────────────────────────────────────────

class _IosAppPanel extends StatelessWidget {
  const _IosAppPanel({
    required this.app,
    required this.topPad,
    required this.bottomPad,
    required this.onClose,
  });

  final DesktopShellApp app;
  final double topPad;
  final double bottomPad;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F0EB),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFCFAF7).withValues(alpha: .98),
              const Color(0xFFF0E9E1).withValues(alpha: .96),
              app.accent.withValues(alpha: .10),
            ],
            stops: const [0, .68, 1],
          ),
          border: Border(
            bottom: BorderSide(color: app.accent.withValues(alpha: .10)),
          ),
        ),
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 280) onClose();
              },
              child: Container(
                padding: EdgeInsets.fromLTRB(14, topPad + 7, 14, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: .76),
                      app.accent.withValues(alpha: .09),
                    ],
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: .58),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _IosCloseButton(accent: app.accent, onTap: onClose),
                        const SizedBox(width: 10),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                app.accent,
                                Color.lerp(app.accent, _IosNexora.dark, .22)!,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: app.accent.withValues(alpha: .28),
                                blurRadius: 14,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Icon(app.icon, color: Colors.white, size: 19),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF0B1623),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                app.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF5E7387),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (app.onHeaderAction != null &&
                            app.headerActionIcon != null) ...[
                          _TitleBarButton(
                            icon: app.headerActionIcon!,
                            accent: app.accent,
                            tooltip: app.headerActionTooltip ?? '',
                            onTap: app.onHeaderAction!,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: .28),
                      Colors.white.withValues(alpha: .05),
                    ],
                  ),
                ),
                child: ClipRect(child: app.child),
              ),
            ),
            Container(
              height: bottomPad > 0 ? bottomPad + 6 : 28,
              color: Colors.transparent,
              alignment: Alignment.center,
              child: Container(
                width: 120,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1623).withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosCloseButton extends StatelessWidget {
  const _IosCloseButton({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: .22)),
        ),
        child: Icon(Icons.chevron_left_rounded, color: accent, size: 24),
      ),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  const _TitleBarButton({
    required this.icon,
    required this.accent,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: .18)),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
      ),
    );
  }
}

class _IosAtmosphere extends StatelessWidget {
  const _IosAtmosphere();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: .58),
            const Color(0xFF331008).withValues(alpha: .30),
            Colors.black.withValues(alpha: .56),
          ],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _IosNexora.teal.withValues(alpha: .12),
              Colors.transparent,
              const Color(0xFF240B04).withValues(alpha: .42),
            ],
          ),
        ),
      ),
    );
  }
}

class _IosWorkspaceHeader extends StatefulWidget {
  const _IosWorkspaceHeader({
    required this.userLabel,
    required this.page,
    required this.pages,
    required this.query,
    required this.onQueryChanged,
  });

  final String userLabel;
  final int page;
  final int pages;
  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  State<_IosWorkspaceHeader> createState() => _IosWorkspaceHeaderState();
}

class _IosWorkspaceHeaderState extends State<_IosWorkspaceHeader> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _IosWorkspaceHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller
        ..text = widget.query
        ..selection = TextSelection.collapsed(offset: widget.query.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name {
    final base = widget.userLabel.split('@').first.trim();
    if (base.isEmpty) return 'Nexora';
    return base
        .split(RegExp(r'[._\-]'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        decoration: _IosNexora.surface(radius: 30, opacity: .24),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_IosNexora.cyan, _IosNexora.teal],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _IosNexora.teal.withValues(alpha: .30),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.blur_on_rounded,
                    color: _IosNexora.dark,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nexora Mobile OS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _IosNexora.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _IosNexora.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _IosNexora.line),
                  ),
                  child: Text(
                    '${widget.page + 1}/${widget.pages}',
                    style: const TextStyle(
                      color: _IosNexora.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: .14)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: .72),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: widget.onQueryChanged,
                      style: const TextStyle(
                        color: _IosNexora.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      cursorColor: _IosNexora.cyan,
                      decoration: InputDecoration(
                        hintText: 'Cerca app, clienti, task',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: .50),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (widget.query.isEmpty)
                    Icon(
                      Icons.mic_none_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: .54),
                    )
                  else
                    GestureDetector(
                      onTap: () => widget.onQueryChanged(''),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: .66),
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

// ─────────────────────────────────────────────────────────────────────────────
// Status bar
// ─────────────────────────────────────────────────────────────────────────────

class _IosStatusBar extends StatelessWidget {
  const _IosStatusBar({
    required this.now,
    required this.userLabel,
    required this.onLogout,
  });

  final DateTime now;
  final String userLabel;
  final VoidCallback onLogout;

  String get _initials {
    final base = userLabel.split('@').first;
    final parts = base.split(RegExp(r'[._\-]'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return base.isNotEmpty ? base[0].toUpperCase() : 'N';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: _IosNexora.surface(radius: 999, opacity: .16),
            child: Text(
              DateFormat('HH:mm  •  EEE d MMM', 'it_IT').format(now),
              style: const TextStyle(
                color: _IosNexora.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          Tooltip(
            message: 'Tieni premuto per uscire',
            child: GestureDetector(
              onLongPress: onLogout,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_IosNexora.cyan, _IosNexora.teal],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _IosNexora.teal.withValues(alpha: .28),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: _IosNexora.dark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pagina griglia
// ─────────────────────────────────────────────────────────────────────────────

class _IosHomePage extends StatelessWidget {
  const _IosHomePage({
    required this.apps,
    required this.columns,
    required this.iconSize,
    required this.onTap,
  });

  final List<DesktopShellApp> apps;
  final int columns;
  final double iconSize;
  final ValueChanged<DesktopShellApp> onTap;

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(18),
          decoration: _IosNexora.surface(radius: 26, opacity: .18),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, color: _IosNexora.ink, size: 22),
              SizedBox(width: 10),
              Text(
                'Nessuna app trovata',
                style: TextStyle(
                  color: _IosNexora.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: iconSize + 36,
        crossAxisSpacing: 4,
      ),
      itemCount: apps.length,
      itemBuilder: (_, i) => _IosAppIcon(
        app: apps[i],
        iconSize: iconSize,
        onTap: () => onTap(apps[i]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Icona app
// ─────────────────────────────────────────────────────────────────────────────

class _IosAppIcon extends StatefulWidget {
  const _IosAppIcon({
    required this.app,
    required this.iconSize,
    required this.onTap,
  });

  final DesktopShellApp app;
  final double iconSize;
  final VoidCallback onTap;

  @override
  State<_IosAppIcon> createState() => _IosAppIconState();
}

class _IosAppIconState extends State<_IosAppIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 160),
      vsync: this,
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.iconSize * 0.225;
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) async {
        await _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icona con superellipse
            Container(
              width: widget.iconSize,
              height: widget.iconSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(widget.app.accent, Colors.white, .10)!,
                    Color.lerp(widget.app.accent, Colors.black, 0.28)!,
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .20)),
                boxShadow: [
                  BoxShadow(
                    color: widget.app.accent.withValues(alpha: .30),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Icon(
                widget.app.icon,
                color: Colors.white,
                size: widget.iconSize * 0.45,
              ),
            ),
            const SizedBox(height: 6),
            // Label
            SizedBox(
              width: widget.iconSize + 18,
              child: Text(
                widget.app.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _IosNexora.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      offset: Offset(0, 1),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dock
// ─────────────────────────────────────────────────────────────────────────────

class _IosDock extends StatelessWidget {
  const _IosDock({
    required this.apps,
    required this.iconSize,
    required this.onTap,
  });

  final List<DesktopShellApp> apps;
  final double iconSize;
  final ValueChanged<DesktopShellApp> onTap;

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: _IosNexora.surface(radius: 36, opacity: .20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: apps
              .map(
                (app) => _IosAppIcon(
                  app: app,
                  iconSize: iconSize,
                  onTap: () => onTap(app),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page dots
// ─────────────────────────────────────────────────────────────────────────────

class _IosPageDots extends StatelessWidget {
  const _IosPageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox(height: 22);
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3.5),
            width: active ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: .38),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wallpaper
// ─────────────────────────────────────────────────────────────────────────────

class _IosWallpaper extends StatelessWidget {
  const _IosWallpaper({this.url});
  final String? url;

  static const _fallback = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2B0D05), Color(0xFF4F1E0E), Color(0xFF3B1409)],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return Container(decoration: _fallback);
    return Image.network(
      u,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => Container(decoration: _fallback),
    );
  }
}
