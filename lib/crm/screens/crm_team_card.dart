import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/crm_store.dart';
import '../models/crm_models.dart';

// ────────────────────────────────────────────────
// CRM Team Management Card
// ────────────────────────────────────────────────

class CrmTeamCard extends StatelessWidget {
  const CrmTeamCard({super.key, required this.store});

  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => _TeamContent(store: store),
    );
  }
}

class _TeamContent extends StatelessWidget {
  const _TeamContent({required this.store});

  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TeamHeader(store: store),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 900;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _MemberList(store: store)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _TeamStats(store: store)),
                ],
              );
            }
            return Column(
              children: [
                _MemberList(store: store),
                const SizedBox(height: 16),
                _TeamStats(store: store),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ── Team Header ──

class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.store});

  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    final team = store.currentTeam;
    final owner = store.userById(team.ownerId);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GussoniBrand.primary, const Color(0xFF3F0C02).withValues(alpha: 0.92)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: const Center(child: Icon(Icons.groups_rounded, size: 28, color: Colors.white)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text('${store.members.length} membri del team', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
                if (owner != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 13, color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text('Proprietario: ${owner.fullName}', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.person_add_outlined, size: 16),
            label: const Text('Invita membro'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              foregroundColor: const Color(0xFF0E1020),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Member List ──

class _MemberList extends StatelessWidget {
  const _MemberList({required this.store});

  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    final members = store.members;

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
              const Icon(Icons.people_outline_rounded, size: 18, color: Color(0xFF7D89A8)),
              const SizedBox(width: 8),
              Text('Membri', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF0C0E1A), borderRadius: BorderRadius.circular(999)),
                child: Text('${members.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB8C0D8))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...members.map((member) => _MemberRow(member: member, store: store)),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.store});

  final CrmTeamMember member;
  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    final user = store.userById(member.userId);
    if (user == null) return const SizedBox.shrink();

    final assignedTasks = store.tasksForUser(user.id).where((t) => t.status != CrmTaskStatus.done).length;
    final ownedDeals = store.deals.where((d) => d.assignedTo == user.id && d.status == DealStatus.open).length;
    final joinedFmt = member.joinedAt != null ? DateFormat('MMM yyyy').format(member.joinedAt!) : '–';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          _TeamAvatar(name: user.fullName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(user.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                    const SizedBox(width: 8),
                    _RoleBadge(role: member.role),
                  ],
                ),
                const SizedBox(height: 3),
                Text(user.email, style: const TextStyle(fontSize: 12, color: Color(0xFF525D78))),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _StatChip(icon: Icons.task_alt_outlined, label: '$assignedTasks task', color: const Color(0xFF0369A1)),
                    const SizedBox(width: 8),
                    _StatChip(icon: Icons.handshake_outlined, label: '$ownedDeals deal', color: GussoniBrand.primary),
                    const SizedBox(width: 8),
                    Text('Dal $joinedFmt', style: const TextStyle(fontSize: 11, color: Color(0xFF1E2130), fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          _StatusDot(status: member.status),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final TeamMemberRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: role.color.withValues(alpha: 0.10),
        border: Border.all(color: role.color.withValues(alpha: 0.30)),
      ),
      child: Text(role.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: role.color)),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final TeamMemberStatus status;

  Color get _color {
    switch (status) {
      case TeamMemberStatus.active:
        return GussoniBrand.primary;
      case TeamMemberStatus.invited:
        return const Color(0xFFD97706);
      case TeamMemberStatus.suspended:
        return const Color(0xFF525D78);
    }
  }

  String get _label {
    switch (status) {
      case TeamMemberStatus.active:
        return 'Attivo';
      case TeamMemberStatus.invited:
        return 'Invitato';
      case TeamMemberStatus.suspended:
        return 'Sospeso';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _label,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _color),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── Team Stats ──

class _TeamStats extends StatelessWidget {
  const _TeamStats({required this.store});

  final CrmStore store;

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 0);
    final members = store.members;

    final memberStats = members.map((m) {
      final user = store.userById(m.userId);
      if (user == null) return null;
      final tasks = store.tasksForUser(user.id);
      final openTasks = tasks.where((t) => t.status != CrmTaskStatus.done && t.status != CrmTaskStatus.cancelled).length;
      final doneTasks = tasks.where((t) => t.status == CrmTaskStatus.done).length;
      final ownedDealValue = store.deals.where((d) => d.assignedTo == user.id && d.status == DealStatus.open).fold(0.0, (s, d) => s + d.value);
      return (user: user, openTasks: openTasks, doneTasks: doneTasks, dealValue: ownedDealValue);
    }).whereType<({CrmUser user, int openTasks, int doneTasks, double dealValue})>().toList();

    return Column(
      children: [
        // Workload overview
        Container(
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
                  const Icon(Icons.bar_chart_rounded, size: 18, color: Color(0xFF7D89A8)),
                  const SizedBox(width: 8),
                  Text('Carico di lavoro', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 16),
              ...memberStats.map((stat) => _WorkloadBar(
                name: stat.user.firstName,
                open: stat.openTasks,
                done: stat.doneTasks,
                maxTasks: memberStats.fold(0, (m, s) => m > s.openTasks + s.doneTasks ? m : s.openTasks + s.doneTasks),
              )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Pipeline ownership
        Container(
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
                  const Icon(Icons.handshake_outlined, size: 18, color: Color(0xFF7D89A8)),
                  const SizedBox(width: 8),
                  Text('Pipeline per membro', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 16),
              ...memberStats.where((s) => s.dealValue > 0).map((stat) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    _TeamAvatar(name: stat.user.fullName, size: 32),
                    const SizedBox(width: 10),
                    Expanded(child: Text(stat.user.firstName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB8C0D8)))),
                    Text(currencyFmt.format(stat.dealValue), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  ],
                ),
              )),
              if (memberStats.every((s) => s.dealValue == 0))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Nessun deal assegnato.', style: TextStyle(color: Color(0xFF525D78), fontSize: 13)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkloadBar extends StatelessWidget {
  const _WorkloadBar({required this.name, required this.open, required this.done, required this.maxTasks});

  final String name;
  final int open;
  final int done;
  final int maxTasks;

  @override
  Widget build(BuildContext context) {
    final total = open + done;
    final fraction = maxTasks > 0 ? total / maxTasks : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB8C0D8)), overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 8,
                    child: Stack(
                      children: [
                        Container(color: const Color(0xFF0C0E1A)),
                        FractionallySizedBox(
                          widthFactor: fraction.clamp(0.0, 1.0),
                          child: Container(color: GussoniBrand.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$open aperti', style: const TextStyle(fontSize: 11, color: Color(0xFF7D89A8), fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamAvatar extends StatelessWidget {
  const _TeamAvatar({required this.name, this.size = 40});

  final String name;
  final double size;

  Color _colorForName(String name) {
    const palette = [Color(0xFF0369A1), Color(0xFF7C3AED), Color(0xFF034F3B), Color(0xFFD97706), Color(0xFF0891B2)];
    final hash = name.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c));
    return palette[hash.abs() % palette.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForName(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Center(child: Text(_initials(name), style: TextStyle(fontSize: size * 0.33, fontWeight: FontWeight.w800, color: color))),
    );
  }
}
