import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../brand_config.dart';
import 'desktop_shell.dart'
    show
        DesktopShellApp,
        DesktopQuickAction,
        DesktopWidgetPane,
        DesktopShellController;
import 'desktop_tray_item.dart';
import '../gussoni/widgets/g_reveal.dart';

/// Shell CRM classica: sidebar di navigazione a sinistra, topbar con ricerca
/// e azioni rapide, contenuto a pagina piena. Sostituisce la metafora
/// "desktop OS" mantenendo le stesse app, azioni e widget.
class CrmShellScaffold extends StatefulWidget {
  const CrmShellScaffold({
    super.key,
    required this.apps,
    required this.userLabel,
    required this.onLogout,
    this.initialSession,
    this.onSessionChanged,
    this.quickActions = const [],
    this.dashboardWidgets = const [],
    this.controller,
    this.initialAppId,
    this.topBarTrailing,
    this.floatingChat,
  });

  final List<DesktopShellApp> apps;
  final String userLabel;
  final VoidCallback onLogout;
  final Map<String, dynamic>? initialSession;
  final ValueChanged<Map<String, dynamic>>? onSessionChanged;
  final List<DesktopQuickAction> quickActions;
  final List<DesktopWidgetPane> dashboardWidgets;
  final DesktopShellController? controller;
  final String? initialAppId;

  /// Controllo extra sempre visibile in topbar (es. timer segnatempo).
  final Widget? topBarTrailing;

  /// Widget flottante fisso in basso a destra (es. chatbot Nexora AI).
  final Widget? floatingChat;

  @override
  State<CrmShellScaffold> createState() => _CrmShellScaffoldState();
}

/// Id sintetico della pagina dashboard (non è una DesktopShellApp).
const String _dashboardId = 'dashboard';

class _NavSection {
  const _NavSection(this.label, this.appIds);
  final String label;
  final List<String> appIds;
}

/// Raggruppamento della sidebar. Le app non elencate finiscono in "Altro".
const List<_NavSection> _navSections = [
  _NavSection('Principale', [_dashboardId, 'stats', 'nexora_ai']),
  _NavSection('CRM', [
    'bandi',
    'companies',
    'contacts',
    'opportunities',
    'quotations',
  ]),
  _NavSection('Lavoro', ['projects', 'tasks', 'calendar', 'clock']),
  _NavSection('Comunicazione', ['threads', 'chat', 'memo']),
  _NavSection('Gestione', ['archive', 'admin', 'settings']),
];

class _CrmShellScaffoldState extends State<CrmShellScaffold>
    with SingleTickerProviderStateMixin {
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

  String _selectedId = _dashboardId;
  final Set<String> _visitedIds = {_dashboardId};
  final List<DesktopTrayItem> _pinnedItems = [];
  bool _sidebarCollapsed = false;
  Timer? _clockTimer;
  Timer? _sessionDebounce;
  DateTime _now = DateTime.now();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleControllerRequest);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _restoreSession();
    _searchCtrl.addListener(() {
      final next = _searchCtrl.text.trim();
      if (next != _searchQuery) {
        setState(() => _searchQuery = next);
      }
    });
  }

  @override
  void didUpdateWidget(covariant CrmShellScaffold oldWidget) {
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
    _sessionDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _handleControllerRequest() {
    final appId = widget.controller?.takePendingAppId();
    if (appId == null) return;
    if (appId == _dashboardId || widget.apps.any((app) => app.id == appId)) {
      _selectPage(appId);
    }
  }

  void _restoreSession() {
    final session = widget.initialSession;
    if (session == null) {
      if (widget.initialAppId != null) _selectedIdSafe(widget.initialAppId!);
      return;
    }
    _sidebarCollapsed = session['sidebarCollapsed'] == true;
    final rawItems = session['trayItems'];
    if (rawItems is List) {
      _pinnedItems.addAll(
        rawItems
            .whereType<Map>()
            .map(
              (item) =>
                  DesktopTrayItem.fromMap(Map<String, dynamic>.from(item)),
            )
            .where((item) => item.id.trim().isNotEmpty)
            .take(5),
      );
    }
    final selected = (session['selectedAppId'] as String?)?.trim();
    if (selected != null && selected.isNotEmpty) {
      _selectedIdSafe(selected);
      return;
    }
    // Compatibilità con la vecchia sessione "a finestre": riapri la finestra
    // che era in primo piano.
    final rawWindows = session['windows'];
    if (rawWindows is List) {
      Map<String, dynamic>? top;
      for (final entry in rawWindows.whereType<Map>()) {
        final data = Map<String, dynamic>.from(entry);
        if (data['minimized'] == true) continue;
        if (top == null ||
            ((data['zIndex'] as num?) ?? 0) > ((top['zIndex'] as num?) ?? 0)) {
          top = data;
        }
      }
      final appId = (top?['appId'] as String?)?.trim();
      if (appId != null) _selectedIdSafe(appId);
    }
  }

  void _selectedIdSafe(String id) {
    if (id == _dashboardId || widget.apps.any((app) => app.id == id)) {
      _selectedId = id;
      _visitedIds.add(id);
    }
  }

  void _scheduleSessionChanged() {
    if (widget.onSessionChanged == null) return;
    _sessionDebounce?.cancel();
    _sessionDebounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      widget.onSessionChanged!({
        'version': 2,
        'selectedAppId': _selectedId,
        'sidebarCollapsed': _sidebarCollapsed,
        'trayItems': _pinnedItems.map((item) => item.toMap()).toList(),
      });
    });
  }

  void _selectPage(String id) {
    if (_selectedId == id) return;
    setState(() {
      _selectedId = id;
      _visitedIds.add(id);
      _searchCtrl.clear();
      _searchQuery = '';
    });
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pageAnimCtrl.value = 1;
    } else {
      _pageAnimCtrl.forward(from: 0);
    }
    _scheduleSessionChanged();
  }

  void _toggleSidebar() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
    _scheduleSessionChanged();
  }

  void _addPinnedItem(DesktopTrayItem item) {
    if (_pinnedItems.any((current) => current.id == item.id) ||
        _pinnedItems.length >= 5) {
      return;
    }
    setState(() => _pinnedItems.add(item));
    _scheduleSessionChanged();
  }

  void _removePinnedItem(String id) {
    setState(() => _pinnedItems.removeWhere((item) => item.id == id));
    _scheduleSessionChanged();
  }

  DesktopShellApp? _appById(String id) =>
      widget.apps.where((app) => app.id == id).firstOrNull;

  List<DesktopShellApp> get _searchResults {
    if (_searchQuery.isEmpty) return const [];
    final query = _searchQuery.toLowerCase();
    return widget.apps
        .where(
          (app) =>
              app.title.toLowerCase().contains(query) ||
              app.subtitle.toLowerCase().contains(query),
        )
        .take(7)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 1240;
    final collapsed = _sidebarCollapsed || isCompact;

    return Scaffold(
      backgroundColor: GussoniBrand.scaffoldBg,
      body: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(
                apps: widget.apps,
                selectedId: _selectedId,
                collapsed: collapsed,
                hasDashboard: widget.dashboardWidgets.isNotEmpty,
                onSelect: _selectPage,
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      searchController: _searchCtrl,
                      searchFocus: _searchFocus,
                      clockLabel: DateFormat(
                        'EEE d MMM • HH:mm',
                        'it_IT',
                      ).format(_now),
                      userLabel: widget.userLabel,
                      quickActions: widget.quickActions,
                      pinnedItems: _pinnedItems,
                      trailing: widget.topBarTrailing,
                      onToggleSidebar: _toggleSidebar,
                      onPinAccepted: _addPinnedItem,
                      onPinRemoved: _removePinnedItem,
                      onOpenSettings: () => _selectPage('settings'),
                      onLogout: widget.onLogout,
                    ),
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
              ),
            ],
          ),
          if (_searchResults.isNotEmpty)
            Positioned(
              top: 72,
              left: (collapsed ? 76 : 248) + 24,
              child: GReveal(
                key: ValueKey(_searchQuery),
                dy: 6,
                child: _SearchResultsPanel(
                  results: _searchResults,
                  onSelect: _selectPage,
                ),
              ),
            ),
          if (widget.floatingChat != null)
            Positioned(right: 20, bottom: 20, child: widget.floatingChat!),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final pageIds = <String>[_dashboardId, ...widget.apps.map((app) => app.id)];
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
          _visitedIds.contains(app.id)
              ? _AppPage(app: app)
              : const SizedBox.shrink(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.apps,
    required this.selectedId,
    required this.collapsed,
    required this.hasDashboard,
    required this.onSelect,
  });

  final List<DesktopShellApp> apps;
  final String selectedId;
  final bool collapsed;
  final bool hasDashboard;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final sectionedIds = _navSections
        .expand((section) => section.appIds)
        .toSet();
    final extraApps = apps
        .where((app) => !sectionedIds.contains(app.id))
        .toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: collapsed ? 76 : 248,
      decoration: const BoxDecoration(
        color: GussoniBrand.surface,
        border: Border(right: BorderSide(color: GussoniBrand.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: collapsed
                ? Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: GussoniBrand.primary,
                      ),
                      child: const Center(
                        child: Text(
                          'G',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  )
                : Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: GussoniBrand.primary,
                    ),
                    child: Image.asset(
                      GussoniBrand.logoWhitePath,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text(
                          'Gussoni Consulenze',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -.2,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const Divider(height: 1, color: GussoniBrand.borderSubtle),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (final section in _navSections) ...[
                  if (!collapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                      child: Text(
                        section.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: GussoniBrand.textMuted,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 10),
                  for (final id in section.appIds)
                    if (id == _dashboardId)
                      (hasDashboard
                          ? _SidebarItem(
                              icon: Icons.space_dashboard_rounded,
                              label: 'Dashboard',
                              accent: GussoniBrand.primary,
                              selected: selectedId == _dashboardId,
                              collapsed: collapsed,
                              onTap: () => onSelect(_dashboardId),
                            )
                          : const SizedBox.shrink())
                    else
                      _sidebarItemFor(id),
                ],
                for (final app in extraApps) _sidebarAppItem(app),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarItemFor(String id) {
    final app = apps.where((a) => a.id == id).firstOrNull;
    if (app == null) return const SizedBox.shrink();
    return _sidebarAppItem(app);
  }

  Widget _sidebarAppItem(DesktopShellApp app) => _SidebarItem(
    icon: app.icon,
    label: app.title,
    accent: app.accent,
    selected: selectedId == app.id,
    collapsed: collapsed,
    onTap: () => onSelect(app.id),
  );
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.accent,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final background = selected
        ? GussoniBrand.primaryBg
        : _hovered
        ? GussoniBrand.surfaceSubtle
        : Colors.transparent;
    final foreground = selected
        ? GussoniBrand.primary
        : GussoniBrand.textSecondary;

    final item = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: widget.collapsed ? 0 : 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(widget.icon, size: 20, color: foreground),
              if (!widget.collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? GussoniBrand.primary
                          : GussoniBrand.textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.collapsed) {
      return Tooltip(message: widget.label, child: item);
    }
    return item;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Topbar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.searchController,
    required this.searchFocus,
    required this.clockLabel,
    required this.userLabel,
    required this.quickActions,
    required this.pinnedItems,
    this.trailing,
    required this.onToggleSidebar,
    required this.onPinAccepted,
    required this.onPinRemoved,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final TextEditingController searchController;
  final FocusNode searchFocus;
  final String clockLabel;
  final String userLabel;
  final List<DesktopQuickAction> quickActions;
  final List<DesktopTrayItem> pinnedItems;
  final Widget? trailing;
  final VoidCallback onToggleSidebar;
  final ValueChanged<DesktopTrayItem> onPinAccepted;
  final ValueChanged<String> onPinRemoved;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: GussoniBrand.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onToggleSidebar,
            tooltip: 'Comprimi menu',
            icon: const Icon(Icons.menu_rounded),
            color: GussoniBrand.textSecondary,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 320,
            height: 40,
            child: TextField(
              controller: searchController,
              focusNode: searchFocus,
              decoration: InputDecoration(
                hintText: 'Cerca sezione…',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: searchController,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: searchController.clear,
                        ),
                ),
                filled: true,
                fillColor: GussoniBrand.scaffoldBg,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: GussoniBrand.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: GussoniBrand.borderSubtle,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: GussoniBrand.primary),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (trailing != null) ...[trailing!, const SizedBox(width: 12)],
          if (pinnedItems.isNotEmpty || quickActions.isNotEmpty)
            _PinnedTray(
              items: pinnedItems,
              onAccept: onPinAccepted,
              onRemove: onPinRemoved,
            ),
          const SizedBox(width: 12),
          if (quickActions.isNotEmpty) ...[
            PopupMenuButton<DesktopQuickAction>(
              tooltip: 'Crea nuovo elemento',
              position: PopupMenuPosition.under,
              onSelected: (action) => action.onTap(),
              itemBuilder: (context) => [
                for (final action in quickActions)
                  PopupMenuItem(
                    value: action,
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: action.accent.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            action.icon,
                            size: 17,
                            color: action.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              action.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              action.subtitle,
                              style: const TextStyle(
                                fontSize: 11,
                                color: GussoniBrand.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: GussoniBrand.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Crea',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Text(
            clockLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GussoniBrand.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          PopupMenuButton<String>(
            tooltip: userLabel,
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'settings') onOpenSettings();
              if (value == 'logout') onLogout();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  userLabel,
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
            child: CircleAvatar(
              radius: 18,
              backgroundColor: GussoniBrand.primary,
              child: Text(
                userLabel.isNotEmpty ? userLabel[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Zona "pin" della topbar: accetta i drag (es. righe di tabella) che prima
/// finivano nel vassoio della notch.
class _PinnedTray extends StatelessWidget {
  const _PinnedTray({
    required this.items,
    required this.onAccept,
    required this.onRemove,
  });

  final List<DesktopTrayItem> items;
  final ValueChanged<DesktopTrayItem> onAccept;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return DragTarget<DesktopTrayItem>(
      onWillAcceptWithDetails: (_) => items.length < 5,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, _) {
        final dragging = candidate.isNotEmpty;
        return PopupMenuButton<String>(
          tooltip: 'Elementi fissati',
          position: PopupMenuPosition.under,
          enabled: items.isNotEmpty,
          itemBuilder: (context) => [
            for (final item in items)
              PopupMenuItem(
                value: item.id,
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      size: 16,
                      color: GussoniBrand.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(
                            item.type,
                            style: const TextStyle(
                              fontSize: 11,
                              color: GussoniBrand.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 14),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onRemove(item.id);
                      },
                    ),
                  ],
                ),
              ),
          ],
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: dragging
                  ? GussoniBrand.primaryBg
                  : GussoniBrand.scaffoldBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: dragging ? GussoniBrand.primary : GussoniBrand.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  dragging ? Icons.add_rounded : Icons.push_pin_outlined,
                  size: 17,
                  color: dragging
                      ? GussoniBrand.primary
                      : GussoniBrand.textSecondary,
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Text(
                    '${items.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: GussoniBrand.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchResultsPanel extends StatelessWidget {
  const _SearchResultsPanel({required this.results, required this.onSelect});

  final List<DesktopShellApp> results;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 340,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: GussoniBrand.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final app in results)
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: app.accent.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(app.icon, size: 17, color: app.accent),
                ),
                title: Text(
                  app.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  app.subtitle,
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => onSelect(app.id),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pagina app (header + contenuto)
// ─────────────────────────────────────────────────────────────────────────────

class _AppPage extends StatelessWidget {
  const _AppPage({required this.app});

  final DesktopShellApp app;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: app.accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(app.icon, color: app.accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.title,
                      style: GoogleFonts.ebGaramond(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: GussoniBrand.textPrimary,
                        letterSpacing: -.2,
                        height: 1.05,
                      ),
                    ),
                    Text(
                      app.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: GussoniBrand.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (app.headerActionIcon != null && app.onHeaderAction != null)
                FilledButton.icon(
                  onPressed: app.onHeaderAction,
                  icon: Icon(app.headerActionIcon, size: 17),
                  label: Text(app.headerActionTooltip ?? 'Nuovo'),
                ),
            ],
          ),
        ),
        Expanded(child: app.child),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class CrmDashboardPage extends StatelessWidget {
  const CrmDashboardPage({
    required this.userLabel,
    required this.now,
    required this.panes,
    required this.quickActions,
    required this.onOpenApp,
  });

  final String userLabel;
  final DateTime now;
  final List<DesktopWidgetPane> panes;
  final List<DesktopQuickAction> quickActions;
  final ValueChanged<String> onOpenApp;

  String get _greeting {
    final hour = now.hour;
    if (hour < 13) return 'Buongiorno';
    if (hour < 18) return 'Buon pomeriggio';
    return 'Buonasera';
  }

  @override
  Widget build(BuildContext context) {
    final name = userLabel.contains('@')
        ? userLabel.split('@').first
        : userLabel;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.all(compact ? 14 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GReveal(
            key: const ValueKey('dash-greeting'),
            dy: 6,
            child: Text(
              '$_greeting, $name',
              style: GoogleFonts.ebGaramond(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: GussoniBrand.textPrimary,
                letterSpacing: -.2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE d MMMM yyyy', 'it_IT').format(now),
            style: const TextStyle(
              fontSize: 13,
              color: GussoniBrand.textMuted,
              fontWeight: FontWeight.w500,
              letterSpacing: .2,
            ),
          ),
          if (quickActions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in quickActions)
                  ActionChip(
                    avatar: Icon(
                      action.icon,
                      size: 16,
                      color: GussoniBrand.primary,
                    ),
                    label: Text(action.label),
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: GussoniBrand.textPrimary,
                    ),
                    backgroundColor: GussoniBrand.surface,
                    side: const BorderSide(color: GussoniBrand.border),
                    onPressed: action.onTap,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 16.0;
              final columns = constraints.maxWidth >= 1320
                  ? 3
                  : constraints.maxWidth >= 880
                  ? 2
                  : 1;
              final cardWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final (i, pane) in panes.indexed)
                    GReveal(
                      key: ValueKey('dash-${pane.id}'),
                      index: i,
                      child: SizedBox(
                        width: cardWidth,
                        height: 280,
                        child: _DashboardCard(pane: pane),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Card chiara della dashboard, in stile Gussoni (superficie crema, bordo
/// caldo, accento per categoria).
class _DashboardCard extends StatefulWidget {
  const _DashboardCard({required this.pane});

  final DesktopWidgetPane pane;

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard> {
  bool _hovered = false;

  DesktopWidgetPane get pane => widget.pane;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: reduceMotion ? 0 : 160),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: GussoniBrand.surface,
          border: Border.all(
            color: _hovered ? GussoniBrand.primaryBorder : GussoniBrand.border,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? const Color(0x145B1205)
                  : const Color(0x081C1D1F),
              blurRadius: _hovered ? 18 : 10,
              offset: Offset(0, _hovered ? 8 : 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: pane.accent.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(pane.icon, size: 17, color: pane.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pane.title,
                        style: const TextStyle(
                          color: GussoniBrand.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (pane.subtitle.isNotEmpty)
                        Text(
                          pane.subtitle,
                          style: const TextStyle(
                            color: GussoniBrand.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: pane.child),
          ],
        ),
      ),
    );
  }
}
