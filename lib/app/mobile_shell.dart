import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../brand_config.dart';
import '../gussoni/widgets/g_reveal.dart';
import 'crm_shell.dart' show CrmDashboardPage;
import 'desktop_shell.dart'
    show
        DesktopShellApp,
        DesktopQuickAction,
        DesktopWidgetPane,
        DesktopShellController;

/// Shell mobile (iPhone-first): header compatto, contenuto a pagina piena,
/// tab bar in basso con i moduli principali e un menu a griglia per il resto.
/// Stesso design system minimale della shell desktop.
class MobileShellScaffold extends StatefulWidget {
  const MobileShellScaffold({
    super.key,
    required this.apps,
    required this.userLabel,
    required this.onLogout,
    this.quickActions = const [],
    this.dashboardWidgets = const [],
    this.controller,
    this.topBarTrailing,
    this.floatingChat,
  });

  final List<DesktopShellApp> apps;
  final String userLabel;
  final VoidCallback onLogout;
  final List<DesktopQuickAction> quickActions;
  final List<DesktopWidgetPane> dashboardWidgets;
  final DesktopShellController? controller;

  /// Controllo sempre visibile in header (es. timer segnatempo).
  final Widget? topBarTrailing;

  /// Widget flottante in basso a destra (es. chatbot Nexora AI).
  final Widget? floatingChat;

  @override
  State<MobileShellScaffold> createState() => _MobileShellScaffoldState();
}

const String _homeId = 'dashboard';

/// Tab fisse della barra inferiore (id app, etichetta, icona).
const List<(String, String, IconData)> _mobileTabs = [
  (_homeId, 'Home', Icons.space_dashboard_rounded),
  ('calendar', 'Agenda', Icons.calendar_month_rounded),
  ('tasks', 'Task', Icons.checklist_rounded),
  ('chat', 'Chat', Icons.forum_rounded),
];

class _MobileShellScaffoldState extends State<MobileShellScaffold>
    with SingleTickerProviderStateMixin {
  String _selectedId = _homeId;
  final Set<String> _visitedIds = {_homeId};
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  late final AnimationController _pageAnimCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late final Animation<double> _pageFade = CurvedAnimation(
    parent: _pageAnimCtrl,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _pageSlide = Tween<Offset>(
    begin: const Offset(0, .012),
    end: Offset.zero,
  ).animate(_pageFade);

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleControllerRequest);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant MobileShellScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleControllerRequest);
      widget.controller?.addListener(_handleControllerRequest);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleControllerRequest);
    _pageAnimCtrl.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _handleControllerRequest() {
    final appId = widget.controller?.takePendingAppId();
    if (appId == null) return;
    if (appId == _homeId || widget.apps.any((app) => app.id == appId)) {
      _selectPage(appId);
    }
  }

  DesktopShellApp? _appById(String id) =>
      widget.apps.where((app) => app.id == id).firstOrNull;

  void _selectPage(String id) {
    if (_selectedId == id) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedId = id;
      _visitedIds.add(id);
    });
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pageAnimCtrl.value = 1;
    } else {
      _pageAnimCtrl.forward(from: 0);
    }
  }

  bool get _selectedInTabs => _mobileTabs.any((tab) => tab.$1 == _selectedId);

  // ── Menu moduli (sheet a griglia) ─────────────────────────────────────────

  Future<void> _openModulesSheet() async {
    HapticFeedback.selectionClick();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ModulesSheet(
        apps: widget.apps,
        selectedId: _selectedId,
        userLabel: widget.userLabel,
        onLogout: widget.onLogout,
      ),
    );
    if (selected != null) _selectPage(selected);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activeApp = _selectedId == _homeId ? null : _appById(_selectedId);

    return Scaffold(
      backgroundColor: GussoniBrand.scaffoldBg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(activeApp),
                Expanded(
                  child: FadeTransition(
                    opacity: _pageFade,
                    child: SlideTransition(
                      position: _pageSlide,
                      child: _buildContent(),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.floatingChat != null)
              Positioned(right: 14, bottom: 14, child: widget.floatingChat!),
          ],
        ),
      ),
      bottomNavigationBar: _buildTabBar(),
    );
  }

  Widget _buildHeader(DesktopShellApp? activeApp) {
    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      decoration: const BoxDecoration(
        color: GussoniBrand.surface,
        border: Border(bottom: BorderSide(color: GussoniBrand.border)),
      ),
      child: Row(
        children: [
          if (activeApp == null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: GussoniBrand.primary,
              ),
              child: const Center(
                child: Text(
                  'G',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Gussoni CRM',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ebGaramond(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: GussoniBrand.textPrimary,
                ),
              ),
            ),
          ] else ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: activeApp.accent.withValues(alpha: .12),
              ),
              child: Icon(activeApp.icon, size: 17, color: activeApp.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                activeApp.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textPrimary,
                  letterSpacing: -.2,
                ),
              ),
            ),
          ],
          if (widget.topBarTrailing != null) ...[
            widget.topBarTrailing!,
            const SizedBox(width: 4),
          ],
          PopupMenuButton<String>(
            tooltip: widget.userLabel,
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'settings') _selectPage('settings');
              if (value == 'logout') widget.onLogout();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  widget.userLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_rounded, size: 17),
                    SizedBox(width: 8),
                    Text('Impostazioni'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 17),
                    SizedBox(width: 8),
                    Text('Esci'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: GussoniBrand.primary,
                child: Text(
                  widget.userLabel.isNotEmpty
                      ? widget.userLabel[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final pageIds = <String>[_homeId, ...widget.apps.map((app) => app.id)];
    final index = pageIds.indexOf(_selectedId).clamp(0, pageIds.length - 1);

    return IndexedStack(
      index: index,
      children: [
        CrmDashboardPage(
          userLabel: widget.userLabel,
          now: _now,
          panes: widget.dashboardWidgets,
          quickActions: widget.quickActions,
          onOpenApp: _selectPage,
        ),
        for (final app in widget.apps)
          _visitedIds.contains(app.id) ? app.child : const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: GussoniBrand.surface,
        border: Border(top: BorderSide(color: GussoniBrand.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (final (id, label, icon) in _mobileTabs)
                Expanded(
                  child: _MobileTabButton(
                    label: label,
                    icon: icon,
                    selected: _selectedId == id,
                    onTap: () => _selectPage(id),
                  ),
                ),
              Expanded(
                child: _MobileTabButton(
                  label: 'Menu',
                  icon: Icons.grid_view_rounded,
                  selected: !_selectedInTabs,
                  onTap: _openModulesSheet,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTabButton extends StatelessWidget {
  const _MobileTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? GussoniBrand.primary : GussoniBrand.textMuted;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(
              color: selected ? GussoniBrand.primaryBg : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet a griglia con tutti i moduli (sostituisce il vecchio launcher OS).
class _ModulesSheet extends StatelessWidget {
  const _ModulesSheet({
    required this.apps,
    required this.selectedId,
    required this.userLabel,
    required this.onLogout,
  });

  final List<DesktopShellApp> apps;
  final String selectedId;
  final String userLabel;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * .78;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: GussoniBrand.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: GussoniBrand.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: GussoniBrand.surfaceMuted,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tutti i moduli',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: GussoniBrand.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onLogout();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 15),
                    label: const Text('Esci'),
                    style: TextButton.styleFrom(
                      foregroundColor: GussoniBrand.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.06,
                ),
                itemCount: apps.length,
                itemBuilder: (context, index) {
                  final app = apps[index];
                  final selected = app.id == selectedId;
                  return GReveal(
                    key: ValueKey('mod-${app.id}'),
                    index: index,
                    stepMs: 22,
                    dy: 6,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).pop(app.id),
                      child: Container(
                        decoration: BoxDecoration(
                          color: selected
                              ? GussoniBrand.primaryBg
                              : GussoniBrand.scaffoldBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? GussoniBrand.primaryBorder
                                : GussoniBrand.borderSubtle,
                          ),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: app.accent.withValues(alpha: .12),
                              ),
                              child: Icon(
                                app.icon,
                                size: 21,
                                color: app.accent,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              app.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: selected
                                    ? GussoniBrand.primary
                                    : GussoniBrand.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
