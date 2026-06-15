import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/browser_fullscreen_hint.dart';
import 'desktop_tray_item.dart';

class DesktopShellApp {
  const DesktopShellApp({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.child,
    this.desktopShortcut = false,
    this.headerActionIcon,
    this.headerActionTooltip,
    this.onHeaderAction,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget child;
  final bool desktopShortcut;
  final IconData? headerActionIcon;
  final String? headerActionTooltip;
  final VoidCallback? onHeaderAction;
}

class DesktopQuickAction {
  const DesktopQuickAction({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
}

class DesktopWidgetPane {
  const DesktopWidgetPane({
    required this.id,
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
    this.subtitle = '',
    this.defaultSize = const Size(280, 208),
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget child;
  final Size defaultSize;
}

class DesktopShellController extends ChangeNotifier {
  String? _pendingAppId;

  void openApp(String appId) {
    _pendingAppId = appId;
    notifyListeners();
  }

  String? _consumePendingAppId() => takePendingAppId();

  /// Consuma la richiesta di apertura app (usato anche dalle shell esterne).
  String? takePendingAppId() {
    final appId = _pendingAppId;
    _pendingAppId = null;
    return appId;
  }
}

class DesktopShellScaffold extends StatefulWidget {
  const DesktopShellScaffold({
    super.key,
    required this.apps,
    required this.userLabel,
    required this.onLogout,
    this.wallpaperUrl,
    this.initialOpenIds = const [],
    this.initialSession,
    this.onSessionChanged,
    this.desktopOverlay,
    this.quickActions = const [],
    this.desktopWidgets = const [],
    this.controller,
  });

  final List<DesktopShellApp> apps;
  final String userLabel;
  final VoidCallback onLogout;
  final String? wallpaperUrl;
  final List<String> initialOpenIds;
  final Map<String, dynamic>? initialSession;
  final ValueChanged<Map<String, dynamic>>? onSessionChanged;
  final Widget? desktopOverlay;
  final List<DesktopQuickAction> quickActions;
  final List<DesktopWidgetPane> desktopWidgets;
  final DesktopShellController? controller;

  @override
  State<DesktopShellScaffold> createState() => _DesktopShellScaffoldState();
}

class _DesktopShellScaffoldState extends State<DesktopShellScaffold> {
  final Map<String, _DesktopWindowState> _windows = {};
  final Map<String, ValueNotifier<Rect>> _rectNotifiers = {};
  final Map<String, _DesktopWidgetState> _widgetStates = {};
  final Map<String, ValueNotifier<Rect>> _widgetRectNotifiers = {};
  final List<DesktopTrayItem> _trayItems = [];
  Timer? _clockTimer;
  Timer? _sessionDebounce;
  DateTime _now = DateTime.now();
  bool _launcherOpen = false;
  Size _desktopSize = Size.zero;
  int _zCounter = 0;
  int _widgetZCounter = 0;
  bool _initialWindowsScheduled = false;
  Offset? _contextMenuPosition;
  static const Set<String> _utilityAppIds = {
    'calendar',
    'chat',
    'memo',
    'threads',
    'settings',
    'stats',
  };
  bool _widgetPickerOpen = false;
  bool _dismissedFullscreenHint = false;
  bool _notchExpanded = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleControllerRequest);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void didUpdateWidget(covariant DesktopShellScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleControllerRequest);
      widget.controller?.addListener(_handleControllerRequest);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleControllerRequest);
    _clockTimer?.cancel();
    _sessionDebounce?.cancel();
    for (final notifier in _rectNotifiers.values) {
      notifier.dispose();
    }
    for (final notifier in _widgetRectNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  void _handleControllerRequest() {
    final appId = widget.controller?._consumePendingAppId();
    if (appId == null || !widget.apps.any((app) => app.id == appId)) {
      return;
    }
    _openApp(appId);
  }

  DesktopWidgetPane _desktopWidgetById(String id) =>
      widget.desktopWidgets.firstWhere((item) => item.id == id);

  List<DesktopShellApp> get _dockApps =>
      widget.apps.where((app) => !_utilityAppIds.contains(app.id)).toList();

  List<DesktopShellApp> get _utilityApps =>
      widget.apps.where((app) => _utilityAppIds.contains(app.id)).toList();

  DesktopShellApp _appById(String id) =>
      widget.apps.firstWhere((app) => app.id == id);

  String? get _activeAppId {
    _DesktopWindowState? top;
    for (final entry in _windows.values) {
      if (entry.minimized) {
        continue;
      }
      if (top == null || entry.zIndex > top.zIndex) {
        top = entry;
      }
    }
    return top?.appId;
  }

  void _ensureInitialWindows() {
    if (_desktopSize == Size.zero ||
        _windows.isNotEmpty ||
        _initialWindowsScheduled) {
      return;
    }
    _initialWindowsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _windows.isNotEmpty) {
        return;
      }
      final restored = _restoreSession(widget.initialSession);
      if (!restored) {
        setState(() {
          for (final id in widget.initialOpenIds) {
            final rect = _defaultRectFor(_windows.length);
            _zCounter += 1;
            _windows[id] = _DesktopWindowState(
              appId: id,
              rect: rect,
              zIndex: _zCounter,
              minimized: false,
              maximized: false,
              restoreRect: rect,
            );
            _rectNotifiers[id] = ValueNotifier<Rect>(rect);
          }
        });
        _scheduleSessionChanged();
      }
    });
  }

  bool _restoreSession(Map<String, dynamic>? session) {
    if (session == null) {
      return false;
    }
    final restoredTrayItems = _restoreTrayItems(session['trayItems']);
    final rawWindows = session['windows'];
    if (rawWindows is! List || rawWindows.isEmpty) {
      if (restoredTrayItems.isNotEmpty) {
        setState(() {
          _trayItems
            ..clear()
            ..addAll(restoredTrayItems);
        });
      }
      return false;
    }

    final restored = <String, _DesktopWindowState>{};
    final restoredNotifiers = <String, ValueNotifier<Rect>>{};
    var maxZ = 0;

    for (final entry in rawWindows) {
      if (entry is! Map) continue;
      final data = Map<String, dynamic>.from(entry);
      final appId = (data['appId'] as String?)?.trim();
      if (appId == null || appId.isEmpty) continue;
      if (!widget.apps.any((app) => app.id == appId)) continue;

      final rect = _clampRect(
        Rect.fromLTWH(
          (data['left'] as num?)?.toDouble() ?? 0,
          (data['top'] as num?)?.toDouble() ?? 0,
          (data['width'] as num?)?.toDouble() ?? 720,
          (data['height'] as num?)?.toDouble() ?? 520,
        ),
      );
      final restoreRect = _clampRect(
        Rect.fromLTWH(
          (data['restoreLeft'] as num?)?.toDouble() ?? rect.left,
          (data['restoreTop'] as num?)?.toDouble() ?? rect.top,
          (data['restoreWidth'] as num?)?.toDouble() ?? rect.width,
          (data['restoreHeight'] as num?)?.toDouble() ?? rect.height,
        ),
      );
      final maximized = data['maximized'] == true;
      final zIndex = (data['zIndex'] as num?)?.toInt() ?? (maxZ + 1);
      maxZ = zIndex > maxZ ? zIndex : maxZ;
      final state = _DesktopWindowState(
        appId: appId,
        rect: maximized ? _maximizedRect() : rect,
        zIndex: zIndex,
        minimized: data['minimized'] == true,
        maximized: maximized,
        restoreRect: restoreRect,
      );
      restored[appId] = state;
      restoredNotifiers[appId] = ValueNotifier<Rect>(state.rect);
    }

    if (restored.isEmpty) {
      if (restoredTrayItems.isNotEmpty) {
        setState(() {
          _trayItems
            ..clear()
            ..addAll(restoredTrayItems);
        });
      }
      return false;
    }

    setState(() {
      _windows
        ..clear()
        ..addAll(restored);
      _rectNotifiers
        ..clear()
        ..addAll(restoredNotifiers);
      _zCounter = maxZ;
      _launcherOpen = session['launcherOpen'] == true;
      _trayItems
        ..clear()
        ..addAll(restoredTrayItems);
    });
    _restoreDesktopWidgets(session['desktopWidgets']);
    return true;
  }

  List<DesktopTrayItem> _restoreTrayItems(dynamic rawItems) {
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map((item) => DesktopTrayItem.fromMap(Map<String, dynamic>.from(item)))
        .where((item) => item.id.trim().isNotEmpty)
        .take(5)
        .toList();
  }

  void _restoreDesktopWidgets(dynamic rawWidgets) {
    for (final n in _widgetRectNotifiers.values) {
      n.dispose();
    }
    _widgetRectNotifiers.clear();
    _widgetStates.clear();
    if (rawWidgets is! List) {
      _ensureWidgetStates();
      return;
    }
    var maxZ = 0;
    for (final entry in rawWidgets) {
      if (entry is! Map) continue;
      final data = Map<String, dynamic>.from(entry);
      final id = (data['id'] as String?)?.trim();
      if (id == null || id.isEmpty) continue;
      if (!widget.desktopWidgets.any((item) => item.id == id)) continue;
      final pane = _desktopWidgetById(id);
      final rect = _clampWidgetRect(
        Rect.fromLTWH(
          (data['left'] as num?)?.toDouble() ?? 0,
          (data['top'] as num?)?.toDouble() ?? 0,
          (data['width'] as num?)?.toDouble() ?? pane.defaultSize.width,
          (data['height'] as num?)?.toDouble() ?? pane.defaultSize.height,
        ),
      );
      final zIndex = (data['zIndex'] as num?)?.toInt() ?? (maxZ + 1);
      maxZ = zIndex > maxZ ? zIndex : maxZ;
      _widgetStates[id] = _DesktopWidgetState(
        id: id,
        rect: rect,
        visible: data['visible'] != false,
        zIndex: zIndex,
      );
      _widgetRectNotifiers[id] = ValueNotifier<Rect>(rect);
    }
    _widgetZCounter = maxZ;
    _ensureWidgetStates();
  }

  void _scheduleSessionChanged() {
    if (widget.onSessionChanged == null || _desktopSize == Size.zero) {
      return;
    }
    _sessionDebounce?.cancel();
    _sessionDebounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      final orderedWindows = _windows.values.toList()
        ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      widget.onSessionChanged!({
        'version': 1,
        'launcherOpen': _launcherOpen,
        'windows': orderedWindows
            .map(
              (window) => {
                'appId': window.appId,
                'left': window.rect.left,
                'top': window.rect.top,
                'width': window.rect.width,
                'height': window.rect.height,
                'restoreLeft': window.restoreRect.left,
                'restoreTop': window.restoreRect.top,
                'restoreWidth': window.restoreRect.width,
                'restoreHeight': window.restoreRect.height,
                'zIndex': window.zIndex,
                'minimized': window.minimized,
                'maximized': window.maximized,
              },
            )
            .toList(),
        'desktopWidgets': _widgetStates.values
            .map(
              (item) => {
                'id': item.id,
                'left': item.rect.left,
                'top': item.rect.top,
                'width': item.rect.width,
                'height': item.rect.height,
                'visible': item.visible,
                'zIndex': item.zIndex,
              },
            )
            .toList(),
        'trayItems': _trayItems.map((item) => item.toMap()).toList(),
      });
    });
  }

  void _addTrayItem(DesktopTrayItem item) {
    if (_trayItems.any((current) => current.id == item.id)) {
      setState(() => _notchExpanded = true);
      return;
    }
    if (_trayItems.length >= 5) {
      setState(() => _notchExpanded = true);
      return;
    }
    setState(() {
      _trayItems.add(item);
      _notchExpanded = true;
    });
    _scheduleSessionChanged();
  }

  void _removeTrayItem(String id) {
    setState(() => _trayItems.removeWhere((item) => item.id == id));
    _scheduleSessionChanged();
  }

  Rect _defaultRectFor(int order) {
    final maxWidth = _desktopSize.width;
    final maxHeight = _desktopSize.height;
    final width = (maxWidth * 0.56).clamp(580.0, 1080.0);
    final height = (maxHeight * 0.64).clamp(420.0, 760.0);
    const leftInset = 16.0;
    const rightInset = 16.0;
    const topInset = 74.0;
    const bottomInset = 96.0;
    final left = leftInset + 108.0 + (order % 4) * 34.0;
    final top = topInset + 18.0 + (order % 4) * 28.0;
    return Rect.fromLTWH(
      left.clamp(leftInset, maxWidth - width - rightInset),
      top.clamp(topInset, maxHeight - height - bottomInset),
      width,
      height,
    );
  }

  Rect _defaultWidgetRectFor(int order, Size size) {
    const rightInset = 28.0;
    const topInset = 104.0;
    final column = order % 2;
    final row = order ~/ 2;
    final left =
        _desktopSize.width -
        rightInset -
        size.width -
        column * (size.width + 18);
    final top = topInset + row * (size.height + 18);
    return _clampWidgetRect(Rect.fromLTWH(left, top, size.width, size.height));
  }

  void _ensureWidgetStates() {
    if (_desktopSize == Size.zero || widget.desktopWidgets.isEmpty) {
      return;
    }
    for (var i = 0; i < widget.desktopWidgets.length; i += 1) {
      final pane = widget.desktopWidgets[i];
      _widgetStates.putIfAbsent(pane.id, () {
        _widgetZCounter += 1;
        final rect = _defaultWidgetRectFor(i, pane.defaultSize);
        _widgetRectNotifiers.putIfAbsent(
          pane.id,
          () => ValueNotifier<Rect>(rect),
        );
        return _DesktopWidgetState(
          id: pane.id,
          rect: rect,
          visible: true,
          zIndex: _widgetZCounter,
        );
      });
      _widgetRectNotifiers.putIfAbsent(
        pane.id,
        () => ValueNotifier<Rect>(_widgetStates[pane.id]!.rect),
      );
    }
  }

  void _focusWindow(String appId) {
    final current = _windows[appId];
    if (current == null) {
      return;
    }
    setState(() {
      _zCounter += 1;
      _windows[appId] = current.copyWith(zIndex: _zCounter, minimized: false);
    });
    _scheduleSessionChanged();
  }

  void _restoreWindow(String appId) {
    final current = _windows[appId];
    if (current == null) {
      return;
    }
    setState(() {
      _zCounter += 1;
      _windows[appId] = current.copyWith(minimized: false, zIndex: _zCounter);
    });
    _scheduleSessionChanged();
  }

  void _openApp(String appId, {bool focusOnly = true}) {
    final existing = _windows[appId];
    if (existing != null) {
      _focusWindow(appId);
      return;
    }
    final rect = _defaultRectFor(_windows.length);
    setState(() {
      _zCounter += 1;
      _windows[appId] = _DesktopWindowState(
        appId: appId,
        rect: rect,
        zIndex: _zCounter,
        minimized: false,
        maximized: false,
        restoreRect: rect,
      );
      _rectNotifiers[appId] = ValueNotifier<Rect>(rect);
    });
    if (focusOnly) {
      _launcherOpen = false;
    }
    _scheduleSessionChanged();
  }

  void _closeWindow(String appId) {
    final notifier = _rectNotifiers.remove(appId);
    notifier?.dispose();
    setState(() => _windows.remove(appId));
    _scheduleSessionChanged();
  }

  void _toggleMinimize(String appId) {
    final current = _windows[appId];
    if (current == null) {
      return;
    }
    setState(() {
      final nextMinimized = !current.minimized;
      _windows[appId] = current.copyWith(minimized: nextMinimized);
      if (current.minimized) {
        _zCounter += 1;
        _windows[appId] = _windows[appId]!.copyWith(zIndex: _zCounter);
      }
    });
    _scheduleSessionChanged();
  }

  void _handleDockTap(String appId) {
    final current = _windows[appId];
    if (current == null) {
      _openApp(appId);
      return;
    }

    if (current.minimized) {
      _restoreWindow(appId);
      return;
    }

    if (_activeAppId == appId) {
      _toggleMinimize(appId);
      return;
    }

    _focusWindow(appId);
  }

  Rect _maximizedRect() {
    const leftInset = 112.0;
    const rightInset = 24.0;
    const topInset = 74.0;
    const bottomInset = 32.0;
    return Rect.fromLTWH(
      leftInset,
      topInset,
      (_desktopSize.width - leftInset - rightInset).clamp(
        620.0,
        double.infinity,
      ),
      (_desktopSize.height - topInset - bottomInset).clamp(
        460.0,
        double.infinity,
      ),
    );
  }

  void _toggleMaximize(String appId) {
    final current = _windows[appId];
    if (current == null) {
      return;
    }
    setState(() {
      _zCounter += 1;
      if (current.maximized) {
        _windows[appId] = current.copyWith(
          rect: current.restoreRect,
          maximized: false,
          zIndex: _zCounter,
        );
      } else {
        final rect = _rectFor(appId);
        _windows[appId] = current.copyWith(
          restoreRect: rect,
          rect: _maximizedRect(),
          maximized: true,
          minimized: false,
          zIndex: _zCounter,
        );
      }
      _rectNotifiers[appId]?.value = _windows[appId]!.rect;
    });
    _scheduleSessionChanged();
  }

  Rect _clampRect(Rect rect) {
    const minWidth = 420.0;
    const minHeight = 280.0;
    const visibleHorizontalSlice = 150.0;
    const visibleTopSlice = 64.0;
    const visibleBottomSlice = 56.0;
    final width = rect.width.clamp(
      minWidth,
      (_desktopSize.width * .96).clamp(minWidth, double.infinity),
    );
    final height = rect.height.clamp(
      minHeight,
      (_desktopSize.height * .96).clamp(minHeight, double.infinity),
    );
    final left = rect.left.clamp(
      -width + visibleHorizontalSlice,
      _desktopSize.width - visibleHorizontalSlice,
    );
    final top = rect.top.clamp(
      -height + visibleTopSlice,
      _desktopSize.height - visibleBottomSlice,
    );
    return Rect.fromLTWH(left, top, width, height);
  }

  Rect _clampWidgetRect(Rect rect) {
    final paneWidth = rect.width.clamp(
      220.0,
      (_desktopSize.width * .42).clamp(220.0, 420.0),
    );
    final paneHeight = rect.height.clamp(
      150.0,
      (_desktopSize.height * .48).clamp(150.0, 280.0),
    );
    final left = rect.left.clamp(12.0, _desktopSize.width - paneWidth - 12.0);
    final top = rect.top.clamp(88.0, _desktopSize.height - paneHeight - 12.0);
    return Rect.fromLTWH(left, top, paneWidth, paneHeight);
  }

  void _focusDesktopWidget(String id) {
    final current = _widgetStates[id];
    if (current == null) return;
    setState(() {
      _widgetZCounter += 1;
      _widgetStates[id] = current.copyWith(
        zIndex: _widgetZCounter,
        visible: true,
      );
    });
    _scheduleSessionChanged();
  }

  void _moveDesktopWidget(String id, Offset delta) {
    final current = _widgetStates[id];
    if (current == null) return;
    final nextRect = _clampWidgetRect(current.rect.shift(delta));
    _widgetStates[id] = current.copyWith(rect: nextRect);
    final notifier = _widgetRectNotifiers[id];
    if (notifier != null && notifier.value != nextRect) {
      notifier.value = nextRect;
    }
    _scheduleSessionChanged();
  }

  void _toggleDesktopWidget(String id, {bool? visible}) {
    final current = _widgetStates[id];
    if (current == null) return;
    setState(() {
      final nextVisible = visible ?? !current.visible;
      _widgetZCounter += 1;
      _widgetStates[id] = current.copyWith(
        visible: nextVisible,
        zIndex: _widgetZCounter,
      );
    });
    _scheduleSessionChanged();
  }

  void _openDesktopContextMenu(Offset position) {
    setState(() {
      _launcherOpen = false;
      _contextMenuPosition = position;
    });
  }

  void _closeDesktopContextMenu() {
    if (_contextMenuPosition == null) return;
    setState(() => _contextMenuPosition = null);
  }

  Widget _buildDesktopWidgets() {
    final visibleWidgets =
        _widgetStates.values.where((item) => item.visible).toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return Stack(
      children: [
        for (final item in visibleWidgets)
          if (_widgetRectNotifiers[item.id] != null)
            ValueListenableBuilder<Rect>(
              key: ValueKey(item.id),
              valueListenable: _widgetRectNotifiers[item.id]!,
              builder: (context, rect, _) {
                return Positioned.fromRect(
                  rect: rect,
                  child: _DesktopWidgetCard(
                    pane: _desktopWidgetById(item.id),
                    onFocus: () => _focusDesktopWidget(item.id),
                    onMove: (delta) => _moveDesktopWidget(item.id, delta),
                    onClose: () =>
                        _toggleDesktopWidget(item.id, visible: false),
                  ),
                );
              },
            ),
      ],
    );
  }

  Widget _buildContextMenu() {
    final position = _contextMenuPosition;
    if (position == null) return const SizedBox.shrink();
    final menuWidth = 324.0;
    const menuHeight = 420.0;
    final left = position.dx.clamp(16.0, _desktopSize.width - menuWidth - 16.0);
    final top = position.dy.clamp(
      84.0,
      _desktopSize.height - menuHeight - 16.0,
    );
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _closeDesktopContextMenu,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: _GlassPanel(
                width: menuWidth,
                height: menuHeight,
                borderRadius: BorderRadius.circular(30),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Azioni rapide',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Crea elementi, apri strumenti e gestisci i widget del desktop.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final action in widget.quickActions)
                                  _ContextActionTile(
                                    label: action.label,
                                    subtitle: action.subtitle,
                                    icon: action.icon,
                                    accent: action.accent,
                                    onTap: () {
                                      _closeDesktopContextMenu();
                                      action.onTap();
                                    },
                                  ),
                              ],
                            ),
                            if (widget.desktopWidgets.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text(
                                'Widget',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .60),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final pane in widget.desktopWidgets)
                                _ContextWidgetRow(
                                  pane: pane,
                                  enabled:
                                      _widgetStates[pane.id]?.visible ?? false,
                                  onTap: () {
                                    _closeDesktopContextMenu();
                                    _toggleDesktopWidget(
                                      pane.id,
                                      visible:
                                          !(_widgetStates[pane.id]?.visible ??
                                              false),
                                    );
                                  },
                                ),
                            ],
                          ],
                        ),
                      ),
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

  Widget _buildWidgetPicker() {
    if (!_widgetPickerOpen || widget.desktopWidgets.isEmpty) {
      return const SizedBox.shrink();
    }
    const panelWidth = 280.0;
    final panelRight = 16.0;
    return Positioned(
      top: 84,
      right: panelRight,
      child: Material(
        color: Colors.transparent,
        child: _GlassPanel(
          width: panelWidth,
          borderRadius: BorderRadius.circular(26),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Widget Desktop',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _WidgetMiniButton(
                    icon: Icons.close_rounded,
                    onTap: () => setState(() => _widgetPickerOpen = false),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Attiva o disattiva i pannelli visibili sul desktop.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .62),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              for (final pane in widget.desktopWidgets)
                _ContextWidgetRow(
                  pane: pane,
                  enabled: _widgetStates[pane.id]?.visible ?? false,
                  onTap: () {
                    setState(() => _widgetPickerOpen = false);
                    _toggleDesktopWidget(
                      pane.id,
                      visible: !(_widgetStates[pane.id]?.visible ?? false),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDock() {
    final apps = _dockApps;
    final viewportHeight = _desktopSize.height.clamp(640.0, 1280.0);
    final heightProgress = ((viewportHeight - 720.0) / 560.0).clamp(0.0, 1.0);
    final maxAvailableHeight = (_desktopSize.height - 78).clamp(280.0, 980.0);
    final availableHeight = maxAvailableHeight;
    final verticalPadding = 14.0 + (10.0 * heightProgress);
    final sidePadding = 10.0 + (3.0 * heightProgress);
    final panelWidth = 96.0 + (14.0 * heightProgress);
    final verticalSpacing = 4.0 + (2.0 * heightProgress);
    final usableHeight = availableHeight - (verticalPadding * 2);
    final slotExtent = usableHeight / apps.length;
    final compact = slotExtent < 68;
    final labelReserve = compact ? 12.0 : 16.0;
    final labelGap = compact ? 3.0 : 5.0;
    final itemExtent = (slotExtent - (verticalSpacing * 2)).clamp(50.0, 106.0);
    final iconBox = (itemExtent - labelReserve - labelGap).clamp(32.0, 70.0);

    final panel = _DesktopChromeSurface(
      width: panelWidth,
      height: availableHeight,
      borderRadius: BorderRadius.circular(36),
      padding: EdgeInsets.fromLTRB(
        sidePadding,
        verticalPadding,
        sidePadding,
        verticalPadding,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final app in apps)
            Padding(
              padding: EdgeInsets.symmetric(vertical: verticalSpacing),
              child: _DockIcon(
                app: app,
                selected: _activeAppId == app.id,
                isOpen: _windows.containsKey(app.id),
                isMinimized: _windows[app.id]?.minimized ?? false,
                onTap: () => _handleDockTap(app.id),
                size: iconBox,
                itemExtent: itemExtent,
                compact: compact,
              ),
            ),
        ],
      ),
    );

    return Positioned(
      left: 16,
      top: 62,
      bottom: 16,
      child: Align(alignment: Alignment.centerLeft, child: panel),
    );
  }

  Widget _buildTopChrome(DesktopShellApp? activeApp) {
    final utilityApps = _utilityApps;
    final splitIndex = (utilityApps.length / 2).ceil();
    final leftApps = utilityApps.take(splitIndex).toList();
    final rightApps = utilityApps.skip(splitIndex).toList();

    return Positioned(
      top: 18,
      left: 16,
      right: 16,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leftApps.isNotEmpty) _buildUtilityCluster(leftApps),
            if (leftApps.isNotEmpty) const SizedBox(width: 14),
            _NotchTray(
              activeTitle: activeApp?.title ?? 'Nexora OS',
              activeSubtitle:
                  activeApp?.subtitle ??
                  'Desktop operativo con app, widget e azioni rapide',
              clockLabel: DateFormat('EEE d MMM • HH:mm', 'it_IT').format(_now),
              items: _trayItems,
              expanded: _notchExpanded,
              hasWidgetPicker: widget.desktopWidgets.isNotEmpty,
              onHoverChanged: (value) => setState(() => _notchExpanded = value),
              onAccept: _addTrayItem,
              onRemove: _removeTrayItem,
              onWidgetPickerTap: widget.desktopWidgets.isEmpty
                  ? null
                  : () {
                      setState(() => _widgetPickerOpen = !_widgetPickerOpen);
                      _closeDesktopContextMenu();
                    },
            ),
            if (rightApps.isNotEmpty) const SizedBox(width: 14),
            if (rightApps.isNotEmpty) _buildUtilityCluster(rightApps),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenHint() {
    final shouldShow =
        !_dismissedFullscreenHint &&
        shouldSuggestBrowserFullscreen(
          viewportWidth: _desktopSize.width,
          viewportHeight: _desktopSize.height,
        );
    if (!shouldShow) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 86,
      left: 0,
      right: 0,
      child: Center(
        child: _DesktopChromeSurface(
          borderRadius: BorderRadius.circular(999),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.open_in_full_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                'Per un’esperienza migliore, apri il browser a tutto schermo.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .88),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              _ToolbarButton(
                icon: Icons.fullscreen_rounded,
                onTap: requestBrowserFullscreen,
              ),
              const SizedBox(width: 8),
              _ToolbarButton(
                icon: Icons.close_rounded,
                onTap: () => setState(() => _dismissedFullscreenHint = true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUtilityCluster(List<DesktopShellApp> apps) {
    return _DesktopChromeSurface(
      borderRadius: BorderRadius.circular(999),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < apps.length; i += 1) ...[
            _UtilityAppButton(
              app: apps[i],
              selected: _activeAppId == apps[i].id,
              isOpen: _windows.containsKey(apps[i].id),
              onTap: () => _handleDockTap(apps[i].id),
            ),
            if (i != apps.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  void _toggleLauncher() {
    setState(() => _launcherOpen = !_launcherOpen);
    _scheduleSessionChanged();
  }

  Rect _rectFor(String appId) =>
      _rectNotifiers[appId]?.value ?? _windows[appId]?.rect ?? Rect.zero;

  void _updateRect(String appId, Rect rect) {
    final current = _windows[appId];
    if (current == null) {
      return;
    }
    final nextRect = _clampRect(rect);
    _windows[appId] = current.copyWith(rect: nextRect, maximized: false);
    final notifier = _rectNotifiers[appId];
    if (notifier != null && notifier.value != nextRect) {
      notifier.value = nextRect;
    }
    _scheduleSessionChanged();
  }

  @override
  Widget build(BuildContext context) {
    final activeApp = _activeAppId == null ? null : _appById(_activeAppId!);

    return LayoutBuilder(
      builder: (context, constraints) {
        _desktopSize = Size(constraints.maxWidth, constraints.maxHeight);
        _ensureInitialWindows();
        _ensureWidgetStates();

        final orderedWindows = _windows.values.toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

        return Shortcuts(
          shortcuts: {
            const SingleActivator(LogicalKeyboardKey.space, meta: true):
                const _ToggleLauncherIntent(),
            const SingleActivator(LogicalKeyboardKey.space, control: true):
                const _ToggleLauncherIntent(),
          },
          child: Actions(
            actions: {
              _ToggleLauncherIntent: CallbackAction<_ToggleLauncherIntent>(
                onInvoke: (intent) {
                  _toggleLauncher();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: const Color(0xFF13161C),
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _closeDesktopContextMenu();
                          if (_widgetPickerOpen) {
                            setState(() => _widgetPickerOpen = false);
                          }
                        },
                        onSecondaryTapDown: (details) =>
                            _openDesktopContextMenu(details.localPosition),
                        child: _DesktopWallpaper(
                          wallpaperUrl: widget.wallpaperUrl,
                        ),
                      ),
                    ),
                    _buildTopChrome(activeApp),
                    _buildFullscreenHint(),
                    if (widget.desktopWidgets.isNotEmpty)
                      _buildDesktopWidgets(),
                    for (final window in orderedWindows)
                      if (!window.minimized)
                        ValueListenableBuilder<Rect>(
                          key: ValueKey(window.appId),
                          valueListenable: _rectNotifiers[window.appId]!,
                          builder: (context, rect, child) {
                            return Positioned.fromRect(
                              rect: rect,
                              child: _DesktopWindow(
                                app: _appById(window.appId),
                                state: window,
                                isActive: window.appId == _activeAppId,
                                onFocus: () => _focusWindow(window.appId),
                                onClose: () => _closeWindow(window.appId),
                                onMinimize: () => _toggleMinimize(window.appId),
                                onMaximize: () => _toggleMaximize(window.appId),
                                onMove: (delta) => _updateRect(
                                  window.appId,
                                  _rectFor(window.appId).shift(delta),
                                ),
                                onResize: (direction, delta) {
                                  Rect next = _rectFor(window.appId);
                                  switch (direction) {
                                    case _ResizeDirection.left:
                                      next = Rect.fromLTRB(
                                        next.left + delta.dx,
                                        next.top,
                                        next.right,
                                        next.bottom,
                                      );
                                    case _ResizeDirection.right:
                                      next = Rect.fromLTRB(
                                        next.left,
                                        next.top,
                                        next.right + delta.dx,
                                        next.bottom,
                                      );
                                    case _ResizeDirection.top:
                                      next = Rect.fromLTRB(
                                        next.left,
                                        next.top + delta.dy,
                                        next.right,
                                        next.bottom,
                                      );
                                    case _ResizeDirection.bottom:
                                      next = Rect.fromLTRB(
                                        next.left,
                                        next.top,
                                        next.right,
                                        next.bottom + delta.dy,
                                      );
                                    case _ResizeDirection.topLeft:
                                      next = Rect.fromLTRB(
                                        next.left + delta.dx,
                                        next.top + delta.dy,
                                        next.right,
                                        next.bottom,
                                      );
                                    case _ResizeDirection.topRight:
                                      next = Rect.fromLTRB(
                                        next.left,
                                        next.top + delta.dy,
                                        next.right + delta.dx,
                                        next.bottom,
                                      );
                                    case _ResizeDirection.bottomLeft:
                                      next = Rect.fromLTRB(
                                        next.left + delta.dx,
                                        next.top,
                                        next.right,
                                        next.bottom + delta.dy,
                                      );
                                    case _ResizeDirection.bottomRight:
                                      next = Rect.fromLTRB(
                                        next.left,
                                        next.top,
                                        next.right + delta.dx,
                                        next.bottom + delta.dy,
                                      );
                                  }
                                  _updateRect(window.appId, next);
                                },
                              ),
                            );
                          },
                        ),
                    if (widget.desktopOverlay != null) widget.desktopOverlay!,
                    if (_contextMenuPosition != null) _buildContextMenu(),
                    _buildWidgetPicker(),
                    _buildDock(),
                    if (_launcherOpen)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _launcherOpen = false);
                            _scheduleSessionChanged();
                          },
                          child: Container(
                            color: Colors.black.withValues(alpha: .20),
                            child: Center(
                              child: _GlassPanel(
                                width: 980,
                                height: 600,
                                borderRadius: BorderRadius.circular(38),
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'App Launcher',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Apri strumenti operativi e pannelli di lavoro come finestre indipendenti.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: .72,
                                        ),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 26),
                                    Expanded(
                                      child: GridView.builder(
                                        itemCount: widget.apps.length,
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 4,
                                              mainAxisSpacing: 18,
                                              crossAxisSpacing: 18,
                                              childAspectRatio: 1.04,
                                            ),
                                        itemBuilder: (context, index) {
                                          final app = widget.apps[index];
                                          return _LauncherTile(
                                            app: app,
                                            selected: _activeAppId == app.id,
                                            onOpen: () {
                                              setState(
                                                () => _launcherOpen = false,
                                              );
                                              _openApp(app.id);
                                              _scheduleSessionChanged();
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotchTray extends StatelessWidget {
  const _NotchTray({
    required this.activeTitle,
    required this.activeSubtitle,
    required this.clockLabel,
    required this.items,
    required this.expanded,
    required this.hasWidgetPicker,
    required this.onHoverChanged,
    required this.onAccept,
    required this.onRemove,
    this.onWidgetPickerTap,
  });

  final String activeTitle;
  final String activeSubtitle;
  final String clockLabel;
  final List<DesktopTrayItem> items;
  final bool expanded;
  final bool hasWidgetPicker;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<DesktopTrayItem> onAccept;
  final ValueChanged<String> onRemove;
  final VoidCallback? onWidgetPickerTap;

  @override
  Widget build(BuildContext context) {
    final width = expanded ? 680.0 : 520.0;
    final height = expanded ? 142.0 : 58.0;
    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: DragTarget<DesktopTrayItem>(
        onWillAcceptWithDetails: (_) => items.length < 5,
        onAcceptWithDetails: (details) => onAccept(details.data),
        builder: (context, candidate, rejected) {
          final dragging = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            width: width,
            height: height,
            child: _GlassPanel(
              width: width,
              height: height,
              borderRadius: BorderRadius.circular(expanded ? 34 : 999),
              padding: EdgeInsets.fromLTRB(
                16,
                expanded ? 14 : 0,
                16,
                expanded ? 14 : 0,
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 58,
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 80),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dragging
                                ? const Color(0xFF5ED0D7).withValues(alpha: .28)
                                : Colors.white.withValues(alpha: .10),
                            border: Border.all(
                              color: dragging
                                  ? const Color(
                                      0xFF5ED0D7,
                                    ).withValues(alpha: .52)
                                  : Colors.white.withValues(alpha: .18),
                            ),
                          ),
                          child: Icon(
                            dragging
                                ? Icons.add_rounded
                                : Icons.drag_indicator_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dragging ? 'Rilascia nel vassoio' : activeTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                dragging
                                    ? '${items.length}/5 elementi salvati'
                                    : activeSubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .68),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          clockLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasWidgetPicker && onWidgetPickerTap != null) ...[
                          const SizedBox(width: 10),
                          _ToolbarButton(
                            icon: Icons.widgets_rounded,
                            onTap: onWidgetPickerTap!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 10),
                    Expanded(
                      child: items.isEmpty
                          ? _NotchEmptyState(isDragging: dragging)
                          : Row(
                              children: [
                                for (final item in items)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _NotchTrayChip(
                                        item: item,
                                        onRemove: () => onRemove(item.id),
                                      ),
                                    ),
                                  ),
                                for (var i = items.length; i < 5; i += 1)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _NotchTraySlot(index: i + 1),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotchEmptyState extends StatelessWidget {
  const _NotchEmptyState({required this.isDragging});
  final bool isDragging;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: .18)),
    ),
    child: Center(
      child: Text(
        isDragging
            ? 'Lascia qui l’elemento'
            : 'Trascina qui fino a 5 elementi da tenere a portata di mano',
        style: TextStyle(
          color: Colors.white.withValues(alpha: .72),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _NotchTraySlot extends StatelessWidget {
  const _NotchTraySlot({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .13)),
    ),
    child: Center(
      child: Text(
        '$index',
        style: TextStyle(
          color: Colors.white.withValues(alpha: .32),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _NotchTrayChip extends StatelessWidget {
  const _NotchTrayChip({required this.item, required this.onRemove});
  final DesktopTrayItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .24)),
    ),
    child: Row(
      children: [
        Icon(item.icon, size: 16, color: Colors.white),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                item.type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .58),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onRemove,
          borderRadius: BorderRadius.circular(999),
          child: Icon(
            Icons.close_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: .70),
          ),
        ),
      ],
    ),
  );
}

class _ToggleLauncherIntent extends Intent {
  const _ToggleLauncherIntent();
}

class _DesktopWindowState {
  const _DesktopWindowState({
    required this.appId,
    required this.rect,
    required this.zIndex,
    required this.minimized,
    required this.maximized,
    required this.restoreRect,
  });

  final String appId;
  final Rect rect;
  final int zIndex;
  final bool minimized;
  final bool maximized;
  final Rect restoreRect;

  _DesktopWindowState copyWith({
    Rect? rect,
    int? zIndex,
    bool? minimized,
    bool? maximized,
    Rect? restoreRect,
  }) {
    return _DesktopWindowState(
      appId: appId,
      rect: rect ?? this.rect,
      zIndex: zIndex ?? this.zIndex,
      minimized: minimized ?? this.minimized,
      maximized: maximized ?? this.maximized,
      restoreRect: restoreRect ?? this.restoreRect,
    );
  }
}

class _DesktopWidgetState {
  const _DesktopWidgetState({
    required this.id,
    required this.rect,
    required this.visible,
    required this.zIndex,
  });

  final String id;
  final Rect rect;
  final bool visible;
  final int zIndex;

  _DesktopWidgetState copyWith({Rect? rect, bool? visible, int? zIndex}) {
    return _DesktopWidgetState(
      id: id,
      rect: rect ?? this.rect,
      visible: visible ?? this.visible,
      zIndex: zIndex ?? this.zIndex,
    );
  }
}

enum _ResizeDirection {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _DesktopWindow extends StatelessWidget {
  const _DesktopWindow({
    super.key,
    required this.app,
    required this.state,
    required this.isActive,
    required this.onFocus,
    required this.onClose,
    required this.onMinimize,
    required this.onMaximize,
    required this.onMove,
    required this.onResize,
  });

  final DesktopShellApp app;
  final _DesktopWindowState state;
  final bool isActive;
  final VoidCallback onFocus;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final ValueChanged<Offset> onMove;
  final void Function(_ResizeDirection direction, Offset delta) onResize;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        onFocus();
      },
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: isActive
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFF8FCFF),
                          const Color(0xFFEDF5FC),
                          app.accent.withValues(alpha: .06),
                        ],
                        stops: const [0, .70, 1],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFF8FCFF).withValues(alpha: .52),
                          const Color(0xFFE7F2FB).withValues(alpha: .42),
                          app.accent.withValues(alpha: .04),
                        ],
                        stops: const [0, .70, 1],
                      ),
                border: Border.all(
                  color: isActive
                      ? Colors.white.withValues(alpha: .80)
                      : Colors.white.withValues(alpha: .30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isActive
                        ? const Color(0x40000000)
                        : const Color(0x18000000),
                    blurRadius: isActive ? 28 : 12,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 62,
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isActive
                            ? [
                                Colors.white.withValues(alpha: .70),
                                app.accent.withValues(alpha: .10),
                              ]
                            : [
                                Colors.white.withValues(alpha: .22),
                                app.accent.withValues(alpha: .04),
                              ],
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: isActive
                              ? Colors.white.withValues(alpha: .60)
                              : Colors.white.withValues(alpha: .28),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        _WindowControlCluster(
                          maximized: state.maximized,
                          onClose: onClose,
                          onMinimize: onMinimize,
                          onMaximize: onMaximize,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) => onFocus(),
                            onPanUpdate: state.maximized
                                ? null
                                : (d) => onMove(d.delta),
                            onDoubleTap: onMaximize,
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    gradient: LinearGradient(
                                      colors: [
                                        app.accent.withValues(alpha: .28),
                                        Colors.white.withValues(alpha: .18),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: .34,
                                      ),
                                    ),
                                  ),
                                  child: Icon(
                                    app.icon,
                                    color: app.accent,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        app.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF0B1623),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        app.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF5E7387),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (app.onHeaderAction != null &&
                            app.headerActionIcon != null) ...[
                          const SizedBox(width: 12),
                          _WindowHeaderActionButton(
                            icon: app.headerActionIcon!,
                            tooltip:
                                app.headerActionTooltip ?? 'Nuovo elemento',
                            onTap: app.onHeaderAction!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: RepaintBoundary(
                      child: _WindowViewport(
                        key: ValueKey('viewport-${app.id}'),
                        child: app.child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!state.maximized) ...[
            _ResizeHandle(direction: _ResizeDirection.left, onResize: onResize),
            _ResizeHandle(
              direction: _ResizeDirection.right,
              onResize: onResize,
            ),
            _ResizeHandle(direction: _ResizeDirection.top, onResize: onResize),
            _ResizeHandle(
              direction: _ResizeDirection.bottom,
              onResize: onResize,
            ),
            _ResizeHandle(
              direction: _ResizeDirection.topLeft,
              onResize: onResize,
            ),
            _ResizeHandle(
              direction: _ResizeDirection.topRight,
              onResize: onResize,
            ),
            _ResizeHandle(
              direction: _ResizeDirection.bottomLeft,
              onResize: onResize,
            ),
            _ResizeHandle(
              direction: _ResizeDirection.bottomRight,
              onResize: onResize,
            ),
          ],
        ],
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.direction, required this.onResize});

  final _ResizeDirection direction;
  final void Function(_ResizeDirection direction, Offset delta) onResize;

  MouseCursor get _cursor => switch (direction) {
    _ResizeDirection.left ||
    _ResizeDirection.right => SystemMouseCursors.resizeLeftRight,
    _ResizeDirection.top ||
    _ResizeDirection.bottom => SystemMouseCursors.resizeUpDown,
    _ResizeDirection.topLeft ||
    _ResizeDirection.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    _ResizeDirection.topRight ||
    _ResizeDirection.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
  };

  @override
  Widget build(BuildContext context) {
    const edge = 10.0;
    const corner = 18.0;
    final handle = MouseRegion(
      cursor: _cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (d) => onResize(direction, d.delta),
        child: const SizedBox.expand(),
      ),
    );

    return switch (direction) {
      _ResizeDirection.left => Positioned(
        left: 0,
        top: 18,
        bottom: 18,
        width: edge,
        child: handle,
      ),
      _ResizeDirection.right => Positioned(
        right: 0,
        top: 18,
        bottom: 18,
        width: edge,
        child: handle,
      ),
      _ResizeDirection.top => Positioned(
        left: 18,
        right: 18,
        top: 0,
        height: edge,
        child: handle,
      ),
      _ResizeDirection.bottom => Positioned(
        left: 18,
        right: 18,
        bottom: 0,
        height: edge,
        child: handle,
      ),
      _ResizeDirection.topLeft => Positioned(
        left: 0,
        top: 0,
        width: corner,
        height: corner,
        child: handle,
      ),
      _ResizeDirection.topRight => Positioned(
        right: 0,
        top: 0,
        width: corner,
        height: corner,
        child: handle,
      ),
      _ResizeDirection.bottomLeft => Positioned(
        left: 0,
        bottom: 0,
        width: corner,
        height: corner,
        child: handle,
      ),
      _ResizeDirection.bottomRight => Positioned(
        right: 0,
        bottom: 0,
        width: corner,
        height: corner,
        child: handle,
      ),
    };
  }
}

class _WindowControlCluster extends StatelessWidget {
  const _WindowControlCluster({
    required this.maximized,
    required this.onClose,
    required this.onMinimize,
    required this.onMaximize,
  });

  final bool maximized;
  final VoidCallback onClose;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF0D1C2D).withValues(alpha: .22),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _WindowControlButton(
            color: const Color(0xFFFC6E5F),
            onTap: onClose,
            icon: Icons.close_rounded,
          ),
          const SizedBox(width: 4),
          _WindowControlButton(
            color: const Color(0xFFFFC243),
            onTap: onMinimize,
            icon: Icons.horizontal_rule_rounded,
          ),
          const SizedBox(width: 4),
          _WindowControlButton(
            color: const Color(0xFF4DC7C4),
            onTap: onMaximize,
            icon: maximized
                ? Icons.fullscreen_exit_rounded
                : Icons.open_in_full_rounded,
          ),
        ],
      ),
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.color,
    required this.onTap,
    required this.icon,
  });

  final Color color;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 30,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: .30),
              color.withValues(alpha: .16),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: .40)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Icon(
            icon,
            size: 14,
            color: Colors.white.withValues(alpha: .92),
          ),
        ),
      ),
    );
  }
}

class _WindowHeaderActionButton extends StatelessWidget {
  const _WindowHeaderActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0xFF0D1C2D).withValues(alpha: .08),
              border: Border.all(
                color: const Color(0xFF4DC7C4).withValues(alpha: .28),
              ),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF0B1623)),
          ),
        ),
      ),
    );
  }
}

class _WindowViewport extends StatefulWidget {
  const _WindowViewport({super.key, required this.child});

  final Widget child;

  @override
  State<_WindowViewport> createState() => _WindowViewportState();
}

class _WindowViewportState extends State<_WindowViewport> {
  late final GlobalKey<NavigatorState> _navigatorKey;

  @override
  void initState() {
    super.initState();
    _navigatorKey = GlobalKey<NavigatorState>();
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navigatorKey,
      onGenerateRoute: (_) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => widget.child,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}

class _DesktopWidgetCard extends StatelessWidget {
  const _DesktopWidgetCard({
    required this.pane,
    required this.onFocus,
    required this.onMove,
    required this.onClose,
  });

  final DesktopWidgetPane pane;
  final VoidCallback onFocus;
  final ValueChanged<Offset> onMove;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onFocus(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF122235).withValues(alpha: .68),
                const Color(0xFF26394D).withValues(alpha: .48),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .16)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 16,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => onFocus(),
                onPanUpdate: (d) => onMove(d.delta),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: pane.accent.withValues(alpha: .18),
                        ),
                        child: Icon(pane.icon, color: pane.accent, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pane.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (pane.subtitle.isNotEmpty)
                              Text(
                                pane.subtitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .58),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onClose,
                        child: _WidgetMiniButton(
                          icon: Icons.close_rounded,
                          onTap: onClose,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: pane.child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WidgetMiniButton extends StatelessWidget {
  const _WidgetMiniButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white.withValues(alpha: .08),
          ),
          child: Icon(
            icon,
            size: 16,
            color: Colors.white.withValues(alpha: .86),
          ),
        ),
      ),
    );
  }
}

class _DesktopShortcut extends StatelessWidget {
  const _DesktopShortcut({
    required this.app,
    required this.selected,
    required this.onOpen,
  });

  final DesktopShellApp app;
  final bool selected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: selected
                  ? app.accent.withValues(alpha: .34)
                  : Colors.white.withValues(alpha: .11),
              border: Border.all(color: Colors.white.withValues(alpha: .18)),
            ),
            child: Icon(app.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            app.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .88),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    required this.app,
    required this.selected,
    required this.isOpen,
    required this.isMinimized,
    required this.onTap,
    this.size = 54,
    this.itemExtent = 72,
    this.compact = false,
  });

  final DesktopShellApp app;
  final bool selected;
  final bool isOpen;
  final bool isMinimized;
  final VoidCallback onTap;
  final double size;
  final double itemExtent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: app.title,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: compact ? 70 : 78,
          height: itemExtent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size <= 40 ? 12 : 18),
                  color: selected
                      ? app.accent.withValues(alpha: .28)
                      : isMinimized
                      ? Colors.white.withValues(alpha: .08)
                      : Colors.white.withValues(alpha: .12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .18),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      app.icon,
                      color: isMinimized
                          ? Colors.white.withValues(alpha: .70)
                          : Colors.white,
                      size: (selected ? size * 0.48 : size * 0.44).clamp(
                        15.0,
                        28.0,
                      ),
                    ),
                    Positioned(
                      bottom: compact ? 4 : 6,
                      child: Container(
                        width: compact ? 5 : 6,
                        height: compact ? 5 : 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isMinimized
                              ? app.accent.withValues(alpha: .75)
                              : isOpen
                              ? Colors.white
                              : Colors.white.withValues(alpha: .28),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 3 : 5),
              Text(
                app.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: .76),
                  fontSize: compact ? 9 : (size <= 42 ? 9 : 11),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LauncherTile extends StatelessWidget {
  const _LauncherTile({
    required this.app,
    required this.selected,
    required this.onOpen,
  });

  final DesktopShellApp app;
  final bool selected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: selected
              ? app.accent.withValues(alpha: .28)
              : Colors.white.withValues(alpha: .08),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white.withValues(alpha: .14),
              ),
              child: Icon(app.icon, color: Colors.white, size: 26),
            ),
            const Spacer(),
            Text(
              app.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              app.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .70),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextActionTile extends StatelessWidget {
  const _ContextActionTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 138,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withValues(alpha: .08),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: accent.withValues(alpha: .18),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .62),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextWidgetRow extends StatelessWidget {
  const _ContextWidgetRow({
    required this.pane,
    required this.enabled,
    required this.onTap,
  });

  final DesktopWidgetPane pane;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: enabled
                  ? Colors.white.withValues(alpha: .12)
                  : Colors.white.withValues(alpha: .05),
              border: Border.all(color: Colors.white.withValues(alpha: .10)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: pane.accent.withValues(alpha: .18),
                  ),
                  child: Icon(pane.icon, color: pane.accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pane.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  enabled
                      ? Icons.visibility_rounded
                      : Icons.add_circle_outline_rounded,
                  color: Colors.white.withValues(alpha: .82),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopChromeSurface extends StatelessWidget {
  const _DesktopChromeSurface({
    required this.child,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    this.borderRadius,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(28);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: width,
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF24364A).withValues(alpha: .68),
              const Color(0xFF0E1724).withValues(alpha: .58),
              Colors.white.withValues(alpha: .10),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .22)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    this.borderRadius,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: width,
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: .22),
              const Color(0xFF1A2D42).withValues(alpha: .26),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .20)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 12,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _UtilityAppButton extends StatelessWidget {
  const _UtilityAppButton({
    required this.app,
    required this.selected,
    required this.isOpen,
    required this.onTap,
  });

  final DesktopShellApp app;
  final bool selected;
  final bool isOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: app.title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: 54,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected
                  ? app.accent.withValues(alpha: .26)
                  : Colors.white.withValues(alpha: .08),
              border: Border.all(
                color: selected
                    ? app.accent.withValues(alpha: .32)
                    : Colors.white.withValues(alpha: .12),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  app.icon,
                  size: 18,
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: .82),
                ),
                Positioned(
                  bottom: 5,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOpen
                          ? Colors.white
                          : Colors.white.withValues(alpha: .24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: .10),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

class _DesktopWallpaper extends StatelessWidget {
  const _DesktopWallpaper({this.wallpaperUrl});

  final String? wallpaperUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF201A1E), Color(0xFF182129), Color(0xFF2B2323)],
        ),
      ),
      child: Stack(
        children: [
          if (wallpaperUrl != null && wallpaperUrl!.trim().isNotEmpty)
            Positioned.fill(
              child: Image.network(
                wallpaperUrl!,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF020817).withValues(alpha: .18),
                    const Color(0xFF04111F).withValues(alpha: .26),
                    const Color(0xFF020617).withValues(alpha: .34),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -120,
            top: -90,
            child: Transform.rotate(
              angle: -.38,
              child: Container(
                width: 500,
                height: 230,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(54),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF36E4DA).withValues(alpha: .24),
                      const Color(0x0036E4DA),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -90,
            top: 124,
            child: Transform.rotate(
              angle: .24,
              child: Container(
                width: 520,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(64),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1D9BF0).withValues(alpha: .24),
                      const Color(0x001D9BF0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 220,
            right: 120,
            bottom: -30,
            child: Transform.rotate(
              angle: -.10,
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(72),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF14B8A6).withValues(alpha: .18),
                      const Color(0x0014B8A6),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _DesktopGridPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .03)
      ..strokeWidth = 1;
    const gap = 44.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
