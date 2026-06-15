import '../../brand_config.dart';
import 'package:flutter/material.dart';

// ────────────────────────────────────────────────
// TlTable – componente tabella stile Teamleader Focus
// Usato da tutte le sezioni lista del CRM
// ────────────────────────────────────────────────

class TlColumn {
  const TlColumn({
    required this.label,
    this.flex = 1,
    this.minWidth,
    this.align = TextAlign.left,
  });
  final String label;
  final int flex;
  final double? minWidth;
  final TextAlign align;
}

class TlCell {
  const TlCell({this.text, this.widget, this.align = TextAlign.left});
  final String? text;
  final Widget? widget;
  final TextAlign align;
}

class TlRow {
  const TlRow({required this.cells, this.onTap, this.key});
  final List<TlCell> cells;
  final VoidCallback? onTap;
  final String? key;
}

// ── Status filter chip ──

class TlStatusFilter {
  const TlStatusFilter({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;
}

// ── Main table widget ──

class TlTable extends StatefulWidget {
  const TlTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onSearch,
    this.searchHint = 'Cerca...',
    this.statusFilters = const [],
    this.selectedStatus,
    this.onStatusChanged,
    this.onAdd,
    this.addLabel,
    this.emptyMessage = 'Nessun elemento trovato.',
    this.pageSizes = const [10, 20, 50],
    this.onPaginationChanged,
    this.extraActions,
  });

  final List<TlColumn> columns;
  final List<TlRow> rows;
  final ValueChanged<String>? onSearch;
  final String searchHint;
  final List<TlStatusFilter> statusFilters;
  final String? selectedStatus;
  final ValueChanged<String?>? onStatusChanged;
  final VoidCallback? onAdd;
  final String? addLabel;
  final String emptyMessage;
  final List<int> pageSizes;
  final void Function(int page, int pageSize)? onPaginationChanged;
  final Widget? extraActions;

  @override
  State<TlTable> createState() => _TlTableState();
}

class _TlTableState extends State<TlTable> {
  int _page = 0;
  int _pageSize = 10;
  String _query = '';
  int? _hoveredRow;

  List<TlRow> get _filtered {
    if (_query.isEmpty) return widget.rows;
    final q = _query.toLowerCase();
    return widget.rows
        .where(
          (r) => r.cells.any((c) {
            final t = c.text?.toLowerCase() ?? '';
            return t.contains(q);
          }),
        )
        .toList();
  }

  List<TlRow> get _paged {
    final f = _filtered;
    final start = _page * _pageSize;
    if (start >= f.length) return [];
    return f.sublist(start, (start + _pageSize).clamp(0, f.length));
  }

  int get _totalPages => (_filtered.length / _pageSize).ceil().clamp(1, 9999);

  void _goTo(int page) {
    if (page >= 0 && page < _totalPages) {
      setState(() => _page = page);
      widget.onPaginationChanged?.call(_page, _pageSize);
    }
  }

  @override
  void didUpdateWidget(TlTable old) {
    super.didUpdateWidget(old);
    if (_page >= _totalPages) setState(() => _page = 0);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final paged = _paged;

    final toolbar = _Toolbar(
      searchHint: widget.searchHint,
      onSearch: (q) => setState(() {
        _query = q;
        _page = 0;
      }),
      statusFilters: widget.statusFilters,
      selectedStatus: widget.selectedStatus,
      onStatusChanged: widget.onStatusChanged,
      onAdd: widget.onAdd,
      addLabel: widget.addLabel,
      extraActions: widget.extraActions,
    );

    final pagination = _Pagination(
      total: filtered.length,
      page: _page,
      totalPages: _totalPages,
      pageSize: _pageSize,
      pageSizes: widget.pageSizes,
      onPage: _goTo,
      onPageSize: (s) {
        setState(() {
          _pageSize = s;
          _page = 0;
        });
        widget.onPaginationChanged?.call(0, s);
      },
    );

    final rowsWidget = paged.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                widget.emptyMessage,
                style: const TextStyle(color: Color(0xFF8C8478), fontSize: 14),
              ),
            ),
          )
        : ListView.separated(
            itemCount: paged.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: Color(0xFFFCFAF7)),
            itemBuilder: (context, i) {
              final row = paged[i];
              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredRow = i),
                onExit: (_) => setState(() => _hoveredRow = null),
                child: InkWell(
                  onTap: row.onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    color: _hoveredRow == i
                        ? const Color(0xFFF0E9E1)
                        : const Color(0xFFFCFAF7),
                    child: _RowWidget(columns: widget.columns, row: row),
                  ),
                ),
              );
            },
          );

    // Usa LayoutBuilder per distinguere contesto bounded (Expanded) da unbounded (ScrollView).
    // In unbounded (SingleChildScrollView) usiamo maxHeight fisso per le righe.
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableDecoration = BoxDecoration(
          color: const Color(0xFFFCFAF7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2D7C9)),
        );

        if (constraints.hasBoundedHeight) {
          // Parent ha altezza definita (Expanded inside Column) → fill space
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toolbar,
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: tableDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(columns: widget.columns),
                      const Divider(height: 1, color: Color(0xFFE2D7C9)),
                      Expanded(child: rowsWidget),
                      const Divider(height: 1, color: Color(0xFFE2D7C9)),
                      pagination,
                    ],
                  ),
                ),
              ),
            ],
          );
        } else {
          // Parent è unbounded (SingleChildScrollView) → altezza fissa per le righe
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toolbar,
              const SizedBox(height: 16),
              Container(
                decoration: tableDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Header(columns: widget.columns),
                    const Divider(height: 1, color: Color(0xFFE2D7C9)),
                    SizedBox(height: 520, child: rowsWidget),
                    const Divider(height: 1, color: Color(0xFFE2D7C9)),
                    pagination,
                  ],
                ),
              ),
            ],
          );
        }
      },
    );
  }
}

// ── Toolbar ──

class _Toolbar extends StatefulWidget {
  const _Toolbar({
    required this.searchHint,
    required this.onSearch,
    required this.statusFilters,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.onAdd,
    required this.addLabel,
    required this.extraActions,
  });
  final String searchHint;
  final ValueChanged<String> onSearch;
  final List<TlStatusFilter> statusFilters;
  final String? selectedStatus;
  final ValueChanged<String?>? onStatusChanged;
  final VoidCallback? onAdd;
  final String? addLabel;
  final Widget? extraActions;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  final _ctrl = TextEditingController();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Search
        SizedBox(
          width: 280,
          height: 40,
          child: TextField(
            controller: _ctrl,
            onChanged: widget.onSearch,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              hintStyle: const TextStyle(
                color: Color(0xFF8C8478),
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF8C8478),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              filled: true,
              fillColor: const Color(0xFFF5F0EB),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2D7C9)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF2E7D4F),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Status filter
        if (widget.statusFilters.isNotEmpty)
          _StatusDropdown(
            filters: widget.statusFilters,
            selected: widget.selectedStatus,
            onChanged: widget.onStatusChanged,
          ),
        const SizedBox(width: 10),
        if (widget.extraActions != null) ...[
          widget.extraActions!,
          const SizedBox(width: 10),
        ],
        const Spacer(),
        // Add button
        if (widget.onAdd != null)
          FilledButton.icon(
            onPressed: widget.onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: Text(widget.addLabel ?? 'Aggiungi'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
      ],
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({
    required this.filters,
    required this.selected,
    required this.onChanged,
  });
  final List<TlStatusFilter> filters;
  final String? selected;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      onSelected: onChanged,
      itemBuilder: (_) => [
        const PopupMenuItem(value: null, child: Text('Tutti')),
        ...filters.map(
          (f) => PopupMenuItem(
            value: f.value,
            child: Row(
              children: [
                if (f.color != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: f.color,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(f.label),
              ],
            ),
          ),
        ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFAF7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2D7C9)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected == null
                  ? 'Status'
                  : filters
                        .firstWhere(
                          (f) => f.value == selected,
                          orElse: () => filters.first,
                        )
                        .label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF54595F)),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: Color(0xFF8C8478),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Column header ──

class _Header extends StatelessWidget {
  const _Header({required this.columns});
  final List<TlColumn> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      color: const Color(0xFFFCFAF7),
      child: Row(
        children: columns.map((col) {
          Widget label = Text(
            col.label,
            textAlign: col.align,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8C8478),
              letterSpacing: 0.3,
            ),
          );
          if (col.minWidth != null) {
            label = SizedBox(width: col.minWidth, child: label);
          } else {
            label = Expanded(flex: col.flex, child: label);
          }
          return label;
        }).toList(),
      ),
    );
  }
}

// ── Row widget ──

class _RowWidget extends StatelessWidget {
  const _RowWidget({required this.columns, required this.row});
  final List<TlColumn> columns;
  final TlRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(columns.length, (i) {
          final col = columns[i];
          final cell = i < row.cells.length ? row.cells[i] : const TlCell();
          Widget content =
              cell.widget ??
              Text(
                cell.text ?? '—',
                textAlign: cell.align,
                style: const TextStyle(fontSize: 13, color: Color(0xFF54595F)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
          if (col.minWidth != null) {
            return SizedBox(width: col.minWidth, child: content);
          }
          return Expanded(flex: col.flex, child: content);
        }),
      ),
    );
  }
}

// ── Pagination ──

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.total,
    required this.page,
    required this.totalPages,
    required this.pageSize,
    required this.pageSizes,
    required this.onPage,
    required this.onPageSize,
  });
  final int total, page, totalPages, pageSize;
  final List<int> pageSizes;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Prev
          _PageBtn(
            icon: Icons.chevron_left,
            onTap: page > 0 ? () => onPage(page - 1) : null,
          ),
          const SizedBox(width: 4),
          // Page numbers
          ..._buildPageNumbers(),
          const SizedBox(width: 4),
          // Next
          _PageBtn(
            icon: Icons.chevron_right,
            onTap: page < totalPages - 1 ? () => onPage(page + 1) : null,
          ),
          const Spacer(),
          // Results count
          Text(
            '$total risultati',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8C8478)),
          ),
          const SizedBox(width: 16),
          // Page size selector
          ...pageSizes.map(
            (s) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => onPageSize(s),
                child: Container(
                  width: 32,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: pageSize == s
                        ? GussoniBrand.primary
                        : const Color(0xFFFCFAF7),
                  ),
                  child: Center(
                    child: Text(
                      '$s',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: pageSize == s
                            ? Colors.white
                            : const Color(0xFF54595F),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageNumbers() {
    final pages = <Widget>[];
    final show = <int>{};
    show.add(0);
    show.add(totalPages - 1);
    for (
      int i = (page - 2).clamp(0, totalPages - 1);
      i <= (page + 2).clamp(0, totalPages - 1);
      i++
    )
      show.add(i);

    final sorted = show.toList()..sort();
    int? prev;
    for (final p in sorted) {
      if (prev != null && p - prev > 1) {
        pages.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '…',
              style: TextStyle(fontSize: 13, color: Color(0xFF8C8478)),
            ),
          ),
        );
      }
      pages.add(
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onPage(p),
            child: Container(
              width: 30,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: p == page ? GussoniBrand.primary : Colors.transparent,
              ),
              child: Center(
                child: Text(
                  '${p + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p == page ? Colors.white : const Color(0xFF54595F),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      prev = p;
    }
    return pages;
  }
}

class _PageBtn extends StatelessWidget {
  const _PageBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: onTap,
    child: Container(
      width: 30,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: const Color(0xFFFCFAF7),
      ),
      child: Icon(
        icon,
        size: 16,
        color: onTap != null
            ? const Color(0xFF54595F)
            : const Color(0xFFE2D7C9),
      ),
    ),
  );
}

// ── Shared badge widget reusable across screens ──

class TlBadge extends StatelessWidget {
  const TlBadge({
    super.key,
    required this.label,
    required this.color,
    this.filled = false,
  });
  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: filled ? color : color.withValues(alpha: 0.10),
      border: filled ? null : Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: filled ? Colors.white : color,
      ),
    ),
  );
}

// ── Primary text cell ──
class TlPrimaryCell extends StatelessWidget {
  const TlPrimaryCell({super.key, required this.text, this.sub});
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1C1D1F),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      if (sub != null)
        Text(
          sub!,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8C8478)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
    ],
  );
}

// ── Amount cell ──
class TlAmountCell extends StatelessWidget {
  const TlAmountCell({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.right,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1C1D1F),
    ),
  );
}

// ── Action menu button ──
class TlRowActions extends StatelessWidget {
  const TlRowActions({super.key, required this.items});
  final List<PopupMenuEntry<String>> items;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    height: 32,
    child: PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, size: 16, color: Color(0xFF8C8478)),
      padding: EdgeInsets.zero,
      itemBuilder: (_) => items,
    ),
  );
}
