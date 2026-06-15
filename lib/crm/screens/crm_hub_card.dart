import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/crm_store.dart';
import '../models/crm_models.dart';

// ────────────────────────────────────────────────
// CRM Hub – overview dashboard card
// ────────────────────────────────────────────────

class CrmHubCard extends StatelessWidget {
  const CrmHubCard({super.key, required this.store});

  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => _CrmHubContent(store: store),
    );
  }
}

class _CrmHubContent extends StatelessWidget {
  const _CrmHubContent({required this.store});

  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    final myTasks = store.tasksForUser(store.currentUser.id)
        .where((t) => t.status != CrmTaskStatus.done && t.status != CrmTaskStatus.cancelled)
        .take(5)
        .toList();
    final recentActivity = store.activityItems.take(8).toList();
    final openDeals = store.deals.where((d) => d.status == DealStatus.open).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── KPI row ──
        _KpiRow(store: store),
        const SizedBox(height: 20),
        // ── Main content ──
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 900;
            if (wide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _ActivityFeed(items: recentActivity, store: store)),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _MyTasksPanel(tasks: myTasks, store: store)),
                  ],
                ),
              );
            }
            return Column(
              children: [
                _ActivityFeed(items: recentActivity, store: store),
                const SizedBox(height: 16),
                _MyTasksPanel(tasks: myTasks, store: store),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        // ── Open deals summary ──
        _OpenDealsSummary(deals: openDeals, store: store),
      ],
    );
  }
}

// ── KPI Row ──

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.store});

  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);

    final kpis = [
      _KpiData(label: 'Aziende', value: '${store.companies.length}', icon: Icons.apartment_rounded, color: const Color(0xFF0369A1), sub: '${store.contacts.length} contatti'),
      _KpiData(label: 'Deal aperti', value: '${store.deals.where((d) => d.status == DealStatus.open).length}', icon: Icons.handshake_outlined, color: GussoniBrand.primary, sub: currencyFmt.format(store.totalOpenDealValue)),
      _KpiData(label: 'Task aperti', value: '${store.openTaskCount}', icon: Icons.task_alt_rounded, color: store.overdueTaskCount > 0 ? const Color(0xFFB91C1C) : GussoniBrand.primary, sub: store.overdueTaskCount > 0 ? '${store.overdueTaskCount} in ritardo' : 'Tutto in orario'),
      _KpiData(label: 'Progetti attivi', value: '${store.activeProjectCount}', icon: Icons.folder_open_rounded, color: const Color(0xFFD97706), sub: '${store.projects.length} totali'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 2 : 1);
        if (columns == 4) {
          return Row(
            children: kpis.map((kpi) => Expanded(child: Padding(
              padding: EdgeInsets.only(left: kpis.indexOf(kpi) > 0 ? 12 : 0),
              child: _KpiCard(data: kpi),
            ))).toList(),
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: kpis.map((kpi) => SizedBox(
            width: (constraints.maxWidth - 12) / columns - 1,
            child: _KpiCard(data: kpi),
          )).toList(),
        );
      },
    );
  }
}

class _KpiData {
  const _KpiData({required this.label, required this.value, required this.icon, required this.color, required this.sub});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String sub;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2130)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(shape: BoxShape.circle, color: data.color.withValues(alpha: 0.12)),
                child: Icon(data.icon, size: 18, color: data.color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(data.value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(data.label, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8), fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(data.sub, style: TextStyle(fontSize: 12, color: data.color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Activity Feed ──

class _ActivityFeed extends StatelessWidget {
  const _ActivityFeed({required this.items, required this.store});

  final List<CrmActivityItem> items;
  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2130)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded, size: 18, color: Color(0xFF7D89A8)),
              const SizedBox(width: 8),
              Text('Attività recenti', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const _EmptyState(message: 'Nessuna attività recente.')
          else
            ...items.map((item) => _ActivityTile(item: item, store: store)),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item, required this.store});

  final CrmActivityItem item;
  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    final actor = store.userById(item.actorId);
    final timeAgo = _timeAgo(item.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UserAvatar(name: actor?.fullName ?? '?', size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: item.iconColor.withValues(alpha: 0.12)),
                      child: Icon(item.icon, size: 12, color: item.iconColor),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(item.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(item.description, style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8)), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 2),
                Text('${actor?.firstName ?? '?'} • $timeAgo', style: const TextStyle(fontSize: 11, color: Color(0xFF525D78), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) {
      return '';
    }
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min fa';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h fa';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}g fa';
    }
    return DateFormat('dd/MM').format(dt);
  }
}

// ── My Tasks Panel ──

class _MyTasksPanel extends StatelessWidget {
  const _MyTasksPanel({required this.tasks, required this.store});

  final List<CrmTask> tasks;
  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2130)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFF7D89A8)),
              const SizedBox(width: 8),
              Text('I miei task', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF0C0E1A), borderRadius: BorderRadius.circular(999)),
                child: Text('${tasks.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB8C0D8))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (tasks.isEmpty)
            const _EmptyState(message: 'Nessun task assegnato.')
          else
            ...tasks.map((task) => _TaskTile(task: task)),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final CrmTask task;

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;
    final dueFmt = task.dueDate != null ? DateFormat('dd/MM').format(task.dueDate!) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(shape: BoxShape.circle, color: task.priority.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _CrmBadge(label: task.status.label, color: task.status.color),
                    if (dueFmt != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.schedule_rounded, size: 11, color: overdue ? const Color(0xFFB91C1C) : const Color(0xFF525D78)),
                      const SizedBox(width: 2),
                      Text(dueFmt, style: TextStyle(fontSize: 11, color: overdue ? const Color(0xFFB91C1C) : const Color(0xFF525D78), fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Open Deals Summary ──

class _OpenDealsSummary extends StatelessWidget {
  const _OpenDealsSummary({required this.deals, required this.store});

  final List<CrmDeal> deals;
  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2130)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.view_kanban_rounded, size: 18, color: Color(0xFF7D89A8)),
              const SizedBox(width: 8),
              Text('Deal aperti', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('Totale pipeline: ${currencyFmt.format(store.totalOpenDealValue)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF034F3B))),
            ],
          ),
          const SizedBox(height: 14),
          if (deals.isEmpty)
            const _EmptyState(message: 'Nessun deal aperto.')
          else
            ...deals.take(5).map((deal) => _DealRow(deal: deal, store: store, currencyFmt: currencyFmt)),
        ],
      ),
    );
  }
}

class _DealRow extends StatelessWidget {
  const _DealRow({required this.deal, required this.store, required this.currencyFmt});

  final CrmDeal deal;
  final CrmStore store;
  final NumberFormat currencyFmt;

  @override
  Widget build(BuildContext context) {
    final stage = store.stageById(deal.stageId);
    final customer = deal.customerType == 'company'
        ? store.companyById(deal.customerId)?.name
        : store.contactById(deal.customerId)?.fullName;
    final assignee = store.userById(deal.assignedTo);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deal.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (customer != null)
                  Text(customer, style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (stage != null) _CrmBadge(label: stage.name, color: stage.color),
          const SizedBox(width: 12),
          Text(currencyFmt.format(deal.value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
          const SizedBox(width: 12),
          if (assignee != null) _UserAvatar(name: assignee.fullName, size: 26),
        ],
      ),
    );
  }
}

// ── Shared widgets ──

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.name, this.size = 32});

  final String name;
  final double size;

  Color _colorForName(String name) {
    const palette = [
      Color(0xFF0369A1), Color(0xFF7C3AED), Color(0xFF034F3B),
      Color(0xFFD97706), Color(0xFFB91C1C), Color(0xFF0891B2),
    ];
    final hash = name.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c));
    return palette[hash.abs() % palette.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForName(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Center(child: Text(_initials(name), style: TextStyle(fontSize: size * 0.35, fontWeight: FontWeight.w800, color: color))),
    );
  }
}

class _CrmBadge extends StatelessWidget {
  const _CrmBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: Text(message, style: const TextStyle(color: Color(0xFF525D78), fontWeight: FontWeight.w500))),
    );
  }
}
