import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/api_client.dart';
import '../data/team_repository.dart';
import '../models/domain_models.dart';
import '../models/roles.dart';
import 'admin_repository.dart';

// ────────────────────────────────────────────────
// Admin Panel – accesso esclusivo per kAdminUid
// Tema scuro, completamente separato dal CRM
// ────────────────────────────────────────────────

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key, required this.user});
  final User user;
  @override State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final _repo = AdminRepository();
  int _selectedSection = 0; // 0=Dashboard 1=Teams 2=Utenti

  static const _sections = ['Dashboard', 'Teams', 'Utenti'];
  static const _icons = [Icons.dashboard_outlined, Icons.groups_outlined, Icons.person_outlined];
  static const _activeIcons = [Icons.dashboard, Icons.groups, Icons.person];

  Future<void> _signOutEverywhere() async {
    await ApiClient.instance.logout();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Row(children: [
        // ── Admin sidebar ──
        Container(
          width: 220,
          color: const Color(0xFF161B22),
          child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFDC2626).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.4))),
                  child: const Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFDC2626), letterSpacing: 1.5)),
                ),
                const SizedBox(height: 10),
                const Text('G-Flux', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                const Text('Pannello amministrativo', style: TextStyle(fontSize: 11, color: Color(0xFF7D89A8))),
              ]),
            ),
            const Divider(color: Color(0xFF21262D), height: 1),
            const SizedBox(height: 8),
            // Nav items
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(children: List.generate(_sections.length, (i) {
                final sel = _selectedSection == i;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _selectedSection = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: sel ? const Color(0xFF21262D) : Colors.transparent,
                      ),
                      child: Row(children: [
                        Icon(_icons[i], size: 17, color: sel ? Colors.white : const Color(0xFF7D89A8)),
                        const SizedBox(width: 10),
                        Text(_sections[i], style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, color: sel ? Colors.white : const Color(0xFF7D89A8))),
                      ]),
                    ),
                  ),
                );
              })),
            )),
            const Divider(color: Color(0xFF21262D), height: 1),
            // Logout
            Padding(
              padding: const EdgeInsets.all(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _signOutEverywhere,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.logout, size: 16, color: Color(0xFF7D89A8)),
                    const SizedBox(width: 10),
                    const Text('Logout', style: TextStyle(fontSize: 13, color: Color(0xFF7D89A8))),
                  ]),
                ),
              ),
            ),
          ])),
        ),
        // ── Content ──
        Expanded(child: _buildContent()),
      ]),
    );
  }

  Widget _buildContent() {
    switch (_selectedSection) {
      case 0: return _DashboardSection(repo: _repo);
      case 1: return _TeamsSection(repo: _repo);
      case 2: return _UsersSection(repo: _repo);
      default: return const SizedBox.shrink();
    }
  }
}

// ── Shared admin widget ──

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child; final EdgeInsets padding;
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: padding,
    decoration: BoxDecoration(color: const Color(0xFF161B22), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF21262D))),
    child: child,
  );
}

class _AdminSectionHeader extends StatelessWidget {
  const _AdminSectionHeader({required this.title, required this.subtitle, this.action});
  final String title; final String subtitle; final Widget? action;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8))),
      ])),
      if (action != null) action!,
    ]),
  );
}

// ────────────────────────────────────────────────
// Dashboard Section
// ────────────────────────────────────────────────

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({required this.repo});
  final AdminRepository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminTeam>>(
      stream: repo.watchAllTeams(),
      builder: (context, snap) {
        final teams = snap.data ?? [];
        final totalUsers = teams.fold(0, (s, t) => s + t.memberCount);
        final activeTeams = teams.where((t) => t.memberCount > 0).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _AdminSectionHeader(title: 'Dashboard', subtitle: 'Panoramica globale della piattaforma'),
            // KPI
            Row(children: [
              Expanded(child: _KpiCard(label: 'Team totali', value: '${teams.length}', icon: Icons.groups_outlined, color: const Color(0xFF3B82F6))),
              const SizedBox(width: 12),
              Expanded(child: _KpiCard(label: 'Utenti totali', value: '$totalUsers', icon: Icons.person_outlined, color: const Color(0xFF10B981))),
              const SizedBox(width: 12),
              Expanded(child: _KpiCard(label: 'Team attivi', value: '$activeTeams', icon: Icons.verified_outlined, color: const Color(0xFFF59E0B))),
              const SizedBox(width: 12),
              Expanded(child: _KpiCard(label: 'Utente admin', value: '1', icon: Icons.shield_outlined, color: const Color(0xFFDC2626))),
            ]),
            const SizedBox(height: 20),
            // Recent teams
            _AdminCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Team recenti', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 14),
              if (teams.isEmpty)
                const Text('Nessun team creato.', style: TextStyle(color: Color(0xFF7D89A8)))
              else
                ...teams.take(5).map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    _TeamAvatar(name: t.name),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text('${t.memberCount} membro/i · Creato ${DateFormat('dd/MM/yyyy').format(t.createdAt)}', style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: const Color(0xFF10B981).withValues(alpha: 0.12), border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3))),
                      child: const Text('Attivo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
                    ),
                  ]),
                )),
            ])),
          ]),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.icon, required this.color});
  final String label; final String value; final IconData icon; final Color color;
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFF161B22), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF21262D))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)), child: Icon(icon, size: 18, color: color)),
      const SizedBox(height: 12),
      Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
    ]),
  );
}

// ────────────────────────────────────────────────
// Teams Section
// ────────────────────────────────────────────────

class _TeamsSection extends StatefulWidget {
  const _TeamsSection({required this.repo});
  final AdminRepository repo;
  @override State<_TeamsSection> createState() => _TeamsSectionState();
}

class _TeamsSectionState extends State<_TeamsSection> {
  AdminTeam? _selected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminTeam>>(
      stream: widget.repo.watchAllTeams(),
      builder: (context, snap) {
        final teams = snap.data ?? [];
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // List
          SizedBox(
            width: _selected != null ? 380 : double.infinity,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _AdminSectionHeader(
                title: 'Teams (${teams.length})',
                subtitle: 'Tutti i team sulla piattaforma',
                action: FilledButton.icon(
                  onPressed: () => _showCreateTeamDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nuovo team'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white),
                ),
              ),
              Expanded(child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: teams.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final t = teams[i];
                  final isSel = _selected?.id == t.id;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selected = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFF21262D) : const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSel ? const Color(0xFF3B82F6).withValues(alpha: 0.5) : const Color(0xFF21262D)),
                      ),
                      child: Row(children: [
                        _TeamAvatar(name: t.name),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                          Text('${t.memberCount} membro/i', style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
                          Text(t.owner?.email ?? '—', style: const TextStyle(fontSize: 11, color: Color(0xFF9AA0BC))),
                        ])),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, size: 18, color: Color(0xFF7D89A8)),
                          color: const Color(0xFF161B22),
                          onSelected: (v) async {
                            if (v == 'delete') {
                              final confirm = await _confirmDelete(context, 'Elimina team "${t.name}"?');
                              if (confirm == true) await widget.repo.deleteTeam(t.id);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'delete', child: Text('Elimina team', style: TextStyle(color: Color(0xFFDC2626)))),
                          ],
                        ),
                      ]),
                    ),
                  );
                },
              )),
            ]),
          ),
          // Detail panel
          if (_selected != null) Expanded(child: _TeamDetailPanel(team: _selected!, repo: widget.repo, onClose: () => setState(() => _selected = null))),
        ]);
      },
    );
  }

  void _showCreateTeamDialog(BuildContext context) {
    showDialog<void>(context: context, builder: (_) => _CreateTeamDialog(repo: widget.repo));
  }

  Future<bool?> _confirmDelete(BuildContext context, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(message, style: const TextStyle(color: Colors.white)),
        content: const Text('Questa azione è irreversibile.', style: TextStyle(color: Color(0xFF7D89A8))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)), child: const Text('Elimina')),
        ],
      ),
    );
  }
}

class _TeamDetailPanel extends StatelessWidget {
  const _TeamDetailPanel({required this.team, required this.repo, required this.onClose});
  final AdminTeam team; final AdminRepository repo; final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFF21262D)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 12, 16), child: Row(children: [
          _TeamAvatar(name: team.name, size: 44),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(team.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
            Text('ID: ${team.id}', style: const TextStyle(fontSize: 11, color: Color(0xFF9AA0BC), fontFamily: 'monospace')),
          ])),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close, size: 18, color: Color(0xFF7D89A8))),
        ])),
        const Divider(color: Color(0xFF21262D), height: 1),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Info
          const Text('DETTAGLI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF9AA0BC), letterSpacing: 1)),
          const SizedBox(height: 10),
          _DetailRow(label: 'Creato il', value: DateFormat('dd/MM/yyyy HH:mm').format(team.createdAt)),
          _DetailRow(label: 'Proprietario', value: team.owner?.displayName ?? '—'),
          _DetailRow(label: 'Membri', value: '${team.memberCount}'),
          const SizedBox(height: 20),
          // Members
          Row(children: [
            const Expanded(child: Text('MEMBRI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF9AA0BC), letterSpacing: 1))),
            InkWell(
              onTap: () => _showAddMemberDialog(context),
              child: const Row(children: [Icon(Icons.add, size: 14, color: Color(0xFF3B82F6)), SizedBox(width: 4), Text('Aggiungi', style: TextStyle(fontSize: 12, color: Color(0xFF3B82F6), fontWeight: FontWeight.w600))]),
            ),
          ]),
          const SizedBox(height: 10),
          ...team.members.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              _MemberChip(initials: m.initials),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                Text('${m.role} · ${m.email}', style: const TextStyle(fontSize: 11, color: Color(0xFF7D89A8))),
              ])),
              if (m.userId != team.ownerId) IconButton(
                onPressed: () => repo.removeMember(teamId: team.id, userId: m.userId),
                icon: const Icon(Icons.remove_circle_outline, size: 16, color: Color(0xFFDC2626)),
                tooltip: 'Rimuovi dal team',
              ),
            ]),
          )),
        ]))),
      ]),
    );
  }

  void _showAddMemberDialog(BuildContext context) {
    showDialog<void>(context: context, builder: (_) => _AddMemberDialog(teamId: team.id, repo: repo));
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label; final String value;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
    SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8)))),
    Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF525D78)))),
  ]));
}

// ────────────────────────────────────────────────
// Users Section
// ────────────────────────────────────────────────

class _UsersSection extends StatelessWidget {
  const _UsersSection({required this.repo});
  final AdminRepository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: repo.watchAllUsers(),
      builder: (context, snap) {
        final users = snap.data ?? [];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _AdminSectionHeader(title: 'Utenti (${users.length})', subtitle: 'Tutti gli account registrati con profilo'),
          Expanded(child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final u = users[i];
              final uid = u['uid'] as String;
              final name = u['displayName'] as String? ?? uid.substring(0, 8);
              final email = u['email'] as String? ?? '—';
              final role = u['role'] as String? ?? '—';
              final teamId = u['teamId'] as String?;
              final isAdmin = uid == kAdminUid;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFF161B22), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF21262D))),
                child: Row(children: [
                  _MemberChip(initials: name.isNotEmpty ? name[0].toUpperCase() : '?'),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                      if (isAdmin) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFDC2626).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: const Text('ADMIN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFDC2626), letterSpacing: 1)))],
                    ]),
                    Text(email, style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
                    Text('$role${teamId != null ? " · Team: ${teamId.substring(0, 12)}..." : " · Nessun team"}', style: const TextStyle(fontSize: 11, color: Color(0xFF9AA0BC))),
                  ])),
                  // Activity button
                  IconButton(
                    icon: const Icon(Icons.bar_chart_outlined, size: 16, color: Color(0xFF7D89A8)),
                    tooltip: 'Attività',
                    onPressed: () => _showActivity(context, uid, name),
                  ),
                ]),
              );
            },
          )),
        ]);
      },
    );
  }

  Future<void> _showActivity(BuildContext context, String uid, String name) async {
    final activity = await repo.getUserActivity(uid);
    if (!context.mounted) return;
    showDialog<void>(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      title: Text('Attività di $name', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _ActivityRow('Segnatempo inseriti', '${activity['timeTracksCount']}'),
        _ActivityRow('Ore totali tracciate', '${(activity['totalHours'] as double).toStringAsFixed(1)}h'),
        _ActivityRow('Task creati', '${activity['tasksCount']}'),
        _ActivityRow('Fatture', '${activity['invoicesCount']}'),
        if (activity['lastActivity'] != null)
          _ActivityRow('Ultima attività', DateFormat('dd/MM/yyyy').format(activity['lastActivity'] as DateTime)),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi'))],
    ));
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.label, this.value);
  final String label; final String value;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
    Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF525D78)))),
    Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
  ]));
}

// ────────────────────────────────────────────────
// Shared admin widgets
// ────────────────────────────────────────────────

class _TeamAvatar extends StatelessWidget {
  const _TeamAvatar({required this.name, this.size = 36});
  final String name; final double size;

  @override
  Widget build(BuildContext context) {
    final init = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * 0.25), color: const Color(0xFF3B82F6).withValues(alpha: 0.15), border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4))),
      child: Center(child: Text(init, style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: const Color(0xFF3B82F6)))),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.initials});
  final String initials;
  @override Widget build(BuildContext context) => Container(
    width: 34, height: 34,
    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF21262D)),
    child: Center(child: Text(initials, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF525D78)))),
  );
}

// ── Dialogs ──

class _CreateTeamDialog extends StatefulWidget {
  const _CreateTeamDialog({required this.repo});
  final AdminRepository repo;
  @override State<_CreateTeamDialog> createState() => _CreateTeamDialogState();
}

class _CreateTeamDialogState extends State<_CreateTeamDialog> {
  final _teamNameCtrl  = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();
  final _ownerNameCtrl  = TextEditingController();
  final _ownerPassCtrl  = TextEditingController();
  bool _saving = false; String? _error;

  @override void dispose() {
    _teamNameCtrl.dispose(); _ownerEmailCtrl.dispose();
    _ownerNameCtrl.dispose(); _ownerPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.repo.createTeam(
        name: _teamNameCtrl.text.trim(),
        ownerEmail: _ownerEmailCtrl.text.trim(),
        ownerDisplayName: _ownerNameCtrl.text.trim(),
        ownerRole: '',   // il primo utente è sempre owner, nessun ruolo
        ownerPassword: _ownerPassCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF161B22),
    title: const Text('Crea nuovo team', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
      _AdminTextField(ctrl: _teamNameCtrl, label: 'Nome team *'),
      const SizedBox(height: 12),
      const Text('Proprietario del team', style: TextStyle(fontSize: 12, color: Color(0xFF7D89A8), fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Il primo utente è sempre Owner — nessun ruolo aggiuntivo.', style: TextStyle(fontSize: 11, color: Color(0xFF525D78))),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _AdminTextField(ctrl: _ownerEmailCtrl, label: 'Email *')),
        const SizedBox(width: 10),
        Expanded(child: _AdminTextField(ctrl: _ownerPassCtrl, label: 'Password *', obscure: true)),
      ]),
      const SizedBox(height: 10),
      _AdminTextField(ctrl: _ownerNameCtrl, label: 'Nome completo'),
      if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12))],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla', style: TextStyle(color: Color(0xFF7D89A8)))),
      FilledButton(onPressed: _saving ? null : _save, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)), child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Crea team')),
    ],
  );
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({required this.teamId, required this.repo});
  final String teamId; final AdminRepository repo;
  @override State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();
  String? _selectedRole;
  bool _saving = false;
  String? _error;

  @override void dispose() {
    _emailCtrl.dispose(); _nameCtrl.dispose(); _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedRole == null) {
      setState(() => _error = 'Seleziona un ruolo.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.repo.addMemberToTeam(
        teamId: widget.teamId,
        email: _emailCtrl.text.trim(),
        displayName: _nameCtrl.text.trim(),
        role: _selectedRole!,
        password: _passCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF161B22),
    title: const Text('Aggiungi membro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: _AdminTextField(ctrl: _emailCtrl, label: 'Email *')),
        const SizedBox(width: 10),
        Expanded(child: _AdminTextField(ctrl: _passCtrl, label: 'Password *', obscure: true)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _AdminTextField(ctrl: _nameCtrl, label: 'Nome completo')),
        const SizedBox(width: 10),
        Expanded(child: _RoleDropdown(value: _selectedRole, onChanged: (v) => setState(() => _selectedRole = v))),
      ]),
      if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12))],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla', style: TextStyle(color: Color(0xFF7D89A8)))),
      FilledButton(onPressed: _saving ? null : _save, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)), child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Aggiungi')),
    ],
  );
}

// Dropdown ruoli condiviso
class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      hint: const Text('Ruolo *', style: TextStyle(fontSize: 12, color: Color(0xFF7D89A8))),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF0D1117),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF21262D))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF21262D))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
      ),
      dropdownColor: const Color(0xFF161B22),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      items: GussoniRoles.all.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
      onChanged: onChanged,
    );
  }
}

class _AdminTextField extends StatelessWidget {
  const _AdminTextField({required this.ctrl, required this.label, this.obscure = false});
  final TextEditingController ctrl; final String label; final bool obscure;
  @override Widget build(BuildContext context) => TextField(
    controller: ctrl,
    obscureText: obscure,
    style: const TextStyle(color: Colors.white, fontSize: 13),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF7D89A8), fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF0D1117),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF21262D))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF21262D))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3B82F6))),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  );
}
