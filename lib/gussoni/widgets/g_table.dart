import 'package:flutter/material.dart';
import '../../app/desktop_tray_item.dart';
import '../../brand_config.dart';
import 'g_reveal.dart';

/// Definizione colonna per GTable.
class GCol<T> {
  const GCol({
    required this.label,
    required this.flex,
    required this.cell,
    this.align = TextAlign.left,
    this.sortable = false,
  });
  final String label;
  final int flex;
  final Widget Function(T item) cell;
  final TextAlign align;
  final bool sortable;
}

class GContextMenuAction {
  const GContextMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.color,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final Color? color;
  final bool destructive;
}

Future<void> showGContextMenu(
  BuildContext context,
  Offset position,
  List<GContextMenuAction> actions,
) async {
  if (actions.isEmpty) return;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final selected = await showMenu<int>(
    context: context,
    color: GussoniBrand.surface,
    elevation: 3,
    shadowColor: Colors.black.withValues(alpha: .30),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: GussoniBrand.border),
    ),
    position: RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      for (var i = 0; i < actions.length; i++)
        PopupMenuItem<int>(
          value: i,
          child: Row(
            children: [
              Icon(
                actions[i].icon,
                size: 17,
                color:
                    actions[i].color ??
                    (actions[i].destructive
                        ? GussoniBrand.error
                        : GussoniBrand.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  actions[i].label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: actions[i].destructive
                        ? GussoniBrand.error
                        : GussoniBrand.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
  if (selected == null) return;
  actions[selected].onSelected();
}

/// Tabella dati standard Gussoni.
/// Usa un header fisso + ListView scrollabile verticalmente.
class GTable<T> extends StatefulWidget {
  const GTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.isSelected,
    this.emptyLabel = 'Nessun elemento trovato.',
    this.emptyIcon = Icons.search_off_outlined,
    this.isLoading = false,
    this.rowsPerPage = 10,
    this.trayItemBuilder,
    this.enableTrayDrag = true,
    this.contextActionsForRow,
  });

  final List<GCol<T>> columns;
  final List<T> rows;
  final void Function(T)? onRowTap;
  final bool Function(T)? isSelected;
  final String emptyLabel;
  final IconData emptyIcon;
  final bool isLoading;
  final int rowsPerPage;
  final DesktopTrayItem Function(T item)? trayItemBuilder;
  final bool enableTrayDrag;
  final List<GContextMenuAction> Function(T item)? contextActionsForRow;

  @override
  State<GTable<T>> createState() => _GTableState<T>();
}

class _GTableState<T> extends State<GTable<T>> {
  int _page = 0;

  @override
  void didUpdateWidget(covariant GTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows.length != widget.rows.length) {
      _page = 0;
      return;
    }
    final maxPage = _maxPage;
    if (_page > maxPage) {
      _page = maxPage;
    }
  }

  int get _maxPage {
    if (widget.rows.isEmpty) {
      return 0;
    }
    return (widget.rows.length - 1) ~/ widget.rowsPerPage;
  }

  @override
  Widget build(BuildContext context) {
    final start = (_page * widget.rowsPerPage).clamp(0, widget.rows.length);
    final end = (start + widget.rowsPerPage).clamp(0, widget.rows.length);
    final pageItems = widget.rows.sublist(start, end);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 560;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: GussoniBrand.glassPanel(radius: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header — solo desktop
              if (!isMobile)
                Container(
                  decoration: const BoxDecoration(
                    color: GussoniBrand.surface,
                    border: Border(
                      bottom: BorderSide(color: GussoniBrand.border),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  child: Row(
                    children: widget.columns
                        .map(
                          (col) => Expanded(
                            flex: col.flex,
                            child: Text(
                              col.label.toUpperCase(),
                              textAlign: col.align,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: GussoniBrand.textMuted,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),

              // Body
              Expanded(
                child: widget.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : widget.rows.isEmpty
                    ? _EmptyState(
                        label: widget.emptyLabel,
                        icon: widget.emptyIcon,
                      )
                    : isMobile
                    ? ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: pageItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final item = pageItems[i];
                          return GReveal(
                            key: ValueKey('m-rv-$_page-$i'),
                            index: i,
                            child: _GMobileRow(
                              columns: widget.columns,
                              item: item,
                              selected: widget.isSelected?.call(item) ?? false,
                              contextActions:
                                  widget.contextActionsForRow?.call(item) ??
                                  const [],
                              onTap: widget.onRowTap != null
                                  ? () => widget.onRowTap!(item)
                                  : null,
                            ),
                          );
                        },
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: pageItems.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          thickness: 1,
                          color: GussoniBrand.borderSubtle,
                        ),
                        itemBuilder: (_, i) {
                          final item = pageItems[i];
                          final selected =
                              widget.isSelected?.call(item) ?? false;
                          return GReveal(
                            key: ValueKey('rv-$_page-$i'),
                            index: i,
                            dy: 6,
                            child: _GRow(
                              columns: widget.columns,
                              item: item,
                              selected: selected,
                              trayItem: widget.enableTrayDrag
                                  ? (widget.trayItemBuilder?.call(item) ??
                                        _defaultTrayItemFor(item))
                                  : null,
                              contextActions:
                                  widget.contextActionsForRow?.call(item) ??
                                  const [],
                              onTap: widget.onRowTap != null
                                  ? () => widget.onRowTap!(item)
                                  : null,
                            ),
                          );
                        },
                      ),
              ),

              if (!widget.isLoading && widget.rows.isNotEmpty)
                _GTablePager(
                  page: _page,
                  rowsPerPage: widget.rowsPerPage,
                  totalItems: widget.rows.length,
                  onPrev: _page == 0
                      ? null
                      : () => setState(
                          () => _page = (_page - 1).clamp(0, _maxPage),
                        ),
                  onNext: _page >= _maxPage
                      ? null
                      : () => setState(
                          () => _page = (_page + 1).clamp(0, _maxPage),
                        ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Mobile card row ──────────────────────────────────────────────────────────

class _GMobileRow<T> extends StatelessWidget {
  const _GMobileRow({
    required this.columns,
    required this.item,
    required this.selected,
    required this.contextActions,
    this.onTap,
  });

  final List<GCol<T>> columns;
  final T item;
  final bool selected;
  final List<GContextMenuAction> contextActions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final int trailingCount = columns.length > 3
        ? 2
        : (columns.length > 2 ? 1 : 0);
    final contentCols = columns.sublist(0, columns.length - trailingCount);
    final trailingCols = columns.sublist(columns.length - trailingCount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trailingMaxWidth = (constraints.maxWidth * .42)
            .clamp(72.0, 150.0)
            .toDouble();
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: contextActions.isEmpty
              ? null
              : (details) => showGContextMenu(
                  context,
                  details.globalPosition,
                  contextActions,
                ),
          onLongPressStart: contextActions.isEmpty
              ? null
              : (details) => showGContextMenu(
                  context,
                  details.globalPosition,
                  contextActions,
                ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: selected ? GussoniBrand.primaryBg : GussoniBrand.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? GussoniBrand.primaryBorder
                      : GussoniBrand.border,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < contentCols.length && i < 3; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i < contentCols.length - 1 ? 2 : 0,
                            ),
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                fontSize: i == 0 ? 14 : 12,
                                fontWeight: i == 0
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: i == 0
                                    ? GussoniBrand.textPrimary
                                    : GussoniBrand.textMuted,
                                overflow: TextOverflow.ellipsis,
                              ),
                              maxLines: 1,
                              child: contentCols[i].cell(item),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailingCols.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: trailingMaxWidth),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final col in trailingCols) col.cell(item),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: GussoniBrand.textMuted.withValues(alpha: .72),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

DesktopTrayItem _defaultTrayItemFor<T>(T item) {
  final dynamic value = item;
  final type = item.runtimeType.toString();
  final title =
      _tryString(() => value.name) ??
      _tryString(() => value.title) ??
      _tryString(() => value.number) ??
      _tryString(() => value.code) ??
      _tryString(() => value.fullName) ??
      type;
  final subtitle =
      _tryString(() => value.email) ??
      _tryString(() => value.companyId) ??
      _tryString(() => value.status) ??
      _tryString(() => value.role) ??
      '';
  final iconKey = _iconKeyForType(type);
  return DesktopTrayItem(
    id: '$type:${title.trim()}:${subtitle.trim()}',
    type: _labelForType(type),
    title: title.trim().isEmpty ? type : title.trim(),
    subtitle: subtitle.trim(),
    iconKey: iconKey,
  );
}

String? _tryString(Object? Function() read) {
  try {
    final value = read();
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}

String _labelForType(String type) {
  final lower = type.toLowerCase();
  if (lower.contains('preventivo') || lower.contains('quotation')) {
    return 'Preventivo';
  }
  if (lower.contains('company')) return 'Societa';
  if (lower.contains('contact')) return 'Contatto';
  if (lower.contains('project')) return 'Progetto';
  if (lower.contains('opportunity') || lower.contains('deal')) {
    return 'Opportunita';
  }
  if (lower.contains('task')) return 'Task';
  if (lower.contains('invoice')) return 'Fattura';
  return 'Elemento';
}

String _iconKeyForType(String type) {
  final lower = type.toLowerCase();
  if (lower.contains('preventivo') || lower.contains('quotation')) {
    return 'quote';
  }
  if (lower.contains('company')) return 'company';
  if (lower.contains('contact')) return 'contact';
  if (lower.contains('project')) return 'project';
  if (lower.contains('opportunity') || lower.contains('deal')) {
    return 'opportunity';
  }
  if (lower.contains('task')) return 'task';
  if (lower.contains('invoice')) return 'invoice';
  return 'pin';
}

class _GTablePager extends StatelessWidget {
  const _GTablePager({
    required this.page,
    required this.rowsPerPage,
    required this.totalItems,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int rowsPerPage;
  final int totalItems;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final from = totalItems == 0 ? 0 : (page * rowsPerPage) + 1;
    final to = ((page + 1) * rowsPerPage).clamp(0, totalItems);
    final totalPages = totalItems == 0
        ? 1
        : ((totalItems - 1) ~/ rowsPerPage) + 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: GussoniBrand.surface,
        border: Border(top: BorderSide(color: GussoniBrand.border)),
      ),
      child: Row(
        children: [
          Text(
            '$from-$to di $totalItems',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GussoniBrand.textMuted,
            ),
          ),
          const Spacer(),
          Text(
            'Pagina ${page + 1} / $totalPages',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GussoniBrand.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: onPrev,
            tooltip: 'Pagina precedente',
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: onNext,
            tooltip: 'Pagina successiva',
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _GRow<T> extends StatefulWidget {
  const _GRow({
    required this.columns,
    required this.item,
    required this.selected,
    required this.contextActions,
    this.trayItem,
    this.onTap,
  });
  final List<GCol<T>> columns;
  final T item;
  final bool selected;
  final List<GContextMenuAction> contextActions;
  final DesktopTrayItem? trayItem;
  final VoidCallback? onTap;

  @override
  State<_GRow<T>> createState() => _GRowState<T>();
}

class _GRowState<T> extends State<_GRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Color bg;
    if (widget.selected) {
      bg = GussoniBrand.primaryBg;
    } else if (_hovered) {
      bg = GussoniBrand.surfaceSubtle;
    } else {
      bg = GussoniBrand.surface;
    }

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.contextActions.isEmpty
            ? null
            : (details) => showGContextMenu(
                context,
                details.globalPosition,
                widget.contextActions,
              ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: widget.columns
                .map(
                  (col) =>
                      Expanded(flex: col.flex, child: col.cell(widget.item)),
                )
                .toList(),
          ),
        ),
      ),
    );

    final trayItem = widget.trayItem;
    if (trayItem == null) {
      return row;
    }
    return Draggable<DesktopTrayItem>(
      data: trayItem,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: _TrayDragFeedback(item: trayItem),
      ),
      childWhenDragging: Opacity(opacity: .52, child: row),
      child: row,
    );
  }
}

class _TrayDragFeedback extends StatelessWidget {
  const _TrayDragFeedback({required this.item});
  final DesktopTrayItem item;

  @override
  Widget build(BuildContext context) => Container(
    width: 230,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: GussoniBrand.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: GussoniBrand.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 18,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      children: [
        Icon(item.icon, size: 18, color: GussoniBrand.primary),
        const SizedBox(width: 10),
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
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: GussoniBrand.textPrimary,
                ),
              ),
              Text(
                item.type,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: GussoniBrand.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36, color: GussoniBrand.textDisabled),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(color: GussoniBrand.textMuted, fontSize: 13),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────
// Layout standard schermata Gussoni
// ─────────────────────────────────────────────

/// Wrapper che fornisce il layout standard:
/// Header (titolo + pulsante azione) → barra ricerca/filtri → tabella.
class GScreenLayout extends StatelessWidget {
  const GScreenLayout({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.action,
    this.filters,
    this.searchHint,
    this.onSearch,
    this.count,
    this.showHeader = true,
    this.contextActions,
    this.isPinned = false,
    this.onPinContext,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? action;
  final Widget? filters;
  final String? searchHint;
  final void Function(String)? onSearch;
  final int? count;
  final bool showHeader;
  final List<GContextMenuAction> Function()? contextActions;
  final bool isPinned;
  final VoidCallback? onPinContext;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final search = onSearch == null
            ? null
            : SizedBox(
                width: compact ? double.infinity : 280,
                child: TextField(
                  onChanged: onSearch,
                  decoration: InputDecoration(
                    hintText: searchHint ?? 'Cerca…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    filled: true,
                    fillColor: GussoniBrand.scaffoldBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: GussoniBrand.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: GussoniBrand.borderSubtle,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: GussoniBrand.primary,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              );

        Widget countBadge() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: GussoniBrand.primaryBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: GussoniBrand.primaryBorder),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: GussoniBrand.primaryDark,
            ),
          ),
        );

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 20 : 22,
                      fontWeight: FontWeight.w900,
                      color: GussoniBrand.textPrimary,
                    ),
                  ),
                ),
                if (count != null) ...[const SizedBox(width: 8), countBadge()],
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: GussoniBrand.textMuted,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        );

        Widget responsiveFilters() {
          final maxWidth = (constraints.maxWidth - (compact ? 24 : 28))
              .clamp(0.0, double.infinity)
              .toDouble();
          return ClipRect(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: maxWidth),
                child: filters!,
              ),
            ),
          );
        }

        Widget responsiveAction() {
          if (action == null) return const SizedBox.shrink();
          final maxWidth = (constraints.maxWidth - (compact ? 24 : 28))
              .clamp(0.0, double.infinity)
              .toDouble();
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              physics: const BouncingScrollPhysics(),
              child: action!,
            ),
          );
        }

        Widget desktopControlsRow() {
          final rightControls = <Widget>[];
          if (search != null) rightControls.add(search);
          if (action != null) {
            if (rightControls.isNotEmpty) {
              rightControls.add(const SizedBox(width: 10));
            }
            rightControls.add(responsiveAction());
          }
          if (onPinContext != null) {
            if (rightControls.isNotEmpty) {
              rightControls.add(const SizedBox(width: 8));
            }
            rightControls.add(
              _AiContextStar(isPinned: isPinned, onToggle: onPinContext!),
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (filters != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: responsiveFilters(),
                  ),
                )
              else
                const Spacer(),
              if (rightControls.isNotEmpty) ...rightControls,
            ],
          );
        }

        final needsToolbar =
            showHeader || search != null || action != null || filters != null;

        final page = Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 0,
            compact ? 8 : 0,
            compact ? 12 : 0,
            compact ? 12 : 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (needsToolbar) ...[
                Container(
                  padding: EdgeInsets.all(compact ? 12 : 14),
                  decoration: BoxDecoration(
                    color: GussoniBrand.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: GussoniBrand.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showHeader) ...[
                        titleBlock,
                        if (search != null ||
                            action != null ||
                            filters != null ||
                            onPinContext != null)
                          const SizedBox(height: 12),
                      ],
                      if (compact) ...[
                        if (search != null) search,
                        if (action != null) ...[
                          SizedBox(height: search != null ? 10 : 0),
                          Align(
                            alignment: Alignment.centerRight,
                            child: responsiveAction(),
                          ),
                        ],
                        if (filters != null) ...[
                          if (search != null || action != null)
                            const SizedBox(height: 12),
                          responsiveFilters(),
                        ],
                      ] else if (search != null ||
                          action != null ||
                          filters != null ||
                          onPinContext != null)
                        desktopControlsRow(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(child: body),
            ],
          ),
        );
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: contextActions == null
              ? null
              : (details) => showGContextMenu(
                  context,
                  details.globalPosition,
                  contextActions!.call(),
                ),
          child: page,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// AI context star button
// ─────────────────────────────────────────────

class _AiContextStar extends StatelessWidget {
  const _AiContextStar({required this.isPinned, required this.onToggle});

  final bool isPinned;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isPinned
          ? 'Contesto Nexora AI attivo — clicca per rimuovere'
          : 'Usa questa schermata come contesto per Nexora AI',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isPinned
                  ? const Color(0xFFFFB800).withValues(alpha: .15)
                  : Colors.transparent,
              border: Border.all(
                color: isPinned
                    ? const Color(0xFFFFB800).withValues(alpha: .50)
                    : Colors.transparent,
              ),
            ),
            child: Icon(
              isPinned ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 18,
              color: isPinned
                  ? const Color(0xFFFFB800)
                  : GussoniBrand.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Shared cell widgets
// ─────────────────────────────────────────────

/// Testo primario cella
class GCellText extends StatelessWidget {
  const GCellText(
    this.text, {
    super.key,
    this.muted = false,
    this.bold = false,
  });
  final String text;
  final bool muted;
  final bool bold;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      color: muted ? GussoniBrand.textMuted : GussoniBrand.textPrimary,
    ),
    overflow: TextOverflow.ellipsis,
    maxLines: 1,
  );
}

/// Chip di stato colorato
class GStatusChip extends StatelessWidget {
  const GStatusChip({
    super.key,
    required this.label,
    required this.color,
    this.small = false,
  });
  final String label;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: small ? 7 : 10,
      vertical: small ? 2 : 3,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: small ? 10 : 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

/// Avatar con iniziali
class GAvatar extends StatelessWidget {
  const GAvatar(this.name, {super.key, this.size = 28, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
              .trim()
              .split(' ')
              .take(2)
              .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
              .join();
    final c = color ?? GussoniBrand.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.withValues(alpha: .12),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w700,
            color: c,
          ),
        ),
      ),
    );
  }
}

// ─── Mobile navigation helpers ────────────────────────────────────────────────

/// Slide animated switcher: mostra lista o dettaglio su mobile.
class GMobileNavWrapper extends StatelessWidget {
  const GMobileNavWrapper({
    super.key,
    required this.showDetail,
    required this.list,
    required this.detail,
  });
  final bool showDetail;
  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, anim) {
        final isDetail = child.key == const ValueKey('_detail_');
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(isDetail ? 1 : -0.3, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      child: showDetail
          ? KeyedSubtree(key: const ValueKey('_detail_'), child: detail)
          : KeyedSubtree(key: const ValueKey('_list_'), child: list),
    );
  }
}

/// Nav bar iOS-style con tasto back per il dettaglio mobile.
class GMobileBackBar extends StatelessWidget {
  const GMobileBackBar({
    super.key,
    required this.backLabel,
    required this.title,
    required this.onBack,
    this.action,
  });
  final String backLabel;
  final String title;
  final VoidCallback onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: GussoniBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GussoniBrand.border),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: onBack,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: GussoniBrand.primary,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chevron_left_rounded, size: 24),
                Text(
                  backLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: GussoniBrand.textPrimary,
              ),
            ),
          ),
          if (action != null) action! else const SizedBox(width: 80),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

/// Pannello dettaglio laterale standard
class GDetailPanel extends StatelessWidget {
  const GDetailPanel({
    super.key,
    required this.title,
    required this.subtitle,
    this.onClose,
    required this.children,
    this.actions = const [],
    this.icon,
  });
  final String title;
  final String subtitle;
  final VoidCallback? onClose;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 560;
      final radius = compact ? 24.0 : 26.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 0,
          compact ? 0 : 0,
          compact ? 12 : 0,
          compact ? 12 : 0,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: GussoniBrand.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: GussoniBrand.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A1C1D1F),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 16,
                  compact ? 14 : 15,
                  10,
                  13,
                ),
                decoration: BoxDecoration(
                  color: GussoniBrand.surface,
                  border: const Border(
                    bottom: BorderSide(color: GussoniBrand.border),
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[icon!, const SizedBox(width: 10)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 17 : 16,
                              fontWeight: FontWeight.w900,
                              color: GussoniBrand.textPrimary,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle,
                                maxLines: compact ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: GussoniBrand.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ...actions,
                    if (onClose != null)
                      IconButton(
                        onPressed: onClose,
                        tooltip: 'Chiudi',
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 17,
                          color: GussoniBrand.textSecondary,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: GussoniBrand.surfaceSubtle,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(34, 34),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(compact ? 12 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...children,
                      SizedBox(height: compact ? 8 : 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Sezione in pannello dettaglio
class GDetailSection extends StatelessWidget {
  const GDetailSection({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: GussoniBrand.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: GussoniBrand.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: GussoniBrand.textMuted,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

/// Riga info chiave→valore in pannello dettaglio
class GInfoRow extends StatelessWidget {
  const GInfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label, value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 320;
      return Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: GussoniBrand.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: valueColor ?? GussoniBrand.textPrimary,
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: GussoniBrand.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: valueColor ?? GussoniBrand.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

/// Filtri pill orizzontali
class GFilterPills<T> extends StatelessWidget {
  const GFilterPills({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.labelOf,
    this.countOf,
  });

  final List<T?> items; // null = "Tutti"
  final T? selected;
  final void Function(T?) onSelect;
  final String Function(T?) labelOf;
  final int Function(T?)? countOf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: items.map((item) {
          final isSel = selected == item;
          final count = countOf?.call(item);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSel ? GussoniBrand.primary : GussoniBrand.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSel ? GussoniBrand.primary : GussoniBrand.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labelOf(item),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSel
                            ? Colors.white
                            : GussoniBrand.textSecondary,
                      ),
                    ),
                    if (count != null && count > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? Colors.white.withValues(alpha: .22)
                              : GussoniBrand.surfaceSubtle,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isSel
                                ? Colors.white
                                : GussoniBrand.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
