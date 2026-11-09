import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/custom_field_models.dart';
import '../data/api_client.dart';
import '../data/team_repository.dart';
import '../models/configuration_package_models.dart';
import '../models/roles.dart';
import 'admin_repository.dart';

// ────────────────────────────────────────────────
// Admin Panel – accesso esclusivo ai profili MySQL con ruolo superadmin
// Tema scuro, completamente separato dal CRM
// ────────────────────────────────────────────────

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key, required this.user});
  final User user;
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final _repo = AdminRepository();
  int _selectedSection = 0; // 0=Dashboard 1=Teams 2=Utenti

  static const _sections = ['Dashboard', 'Teams', 'Utenti'];
  static const _icons = [
    Icons.dashboard_outlined,
    Icons.groups_outlined,
    Icons.person_outlined,
  ];
  static const _activeIcons = [Icons.dashboard, Icons.groups, Icons.person];

  Future<void> _signOutEverywhere() async {
    await ApiClient.instance.logout();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Row(
        children: [
          // ── Admin sidebar ──
          Container(
            width: 220,
            color: const Color(0xFF161B22),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFDC2626,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(
                                0xFFDC2626,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Text(
                            'ADMIN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFDC2626),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'G-Flux',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'Pannello amministrativo',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7D89A8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFF21262D), height: 1),
                  const SizedBox(height: 8),
                  // Nav items
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: List.generate(_sections.length, (i) {
                          final sel = _selectedSection == i;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() => _selectedSection = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: sel
                                      ? const Color(0xFF21262D)
                                      : Colors.transparent,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _icons[i],
                                      size: 17,
                                      color: sel
                                          ? Colors.white
                                          : const Color(0xFF7D89A8),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _sections[i],
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: sel
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: sel
                                            ? Colors.white
                                            : const Color(0xFF7D89A8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  const Divider(color: Color(0xFF21262D), height: 1),
                  // Logout
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _signOutEverywhere,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.logout,
                              size: 16,
                              color: Color(0xFF7D89A8),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF7D89A8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Content ──
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedSection) {
      case 0:
        return _DashboardSection(repo: _repo);
      case 1:
        return _TeamsSection(repo: _repo);
      case 2:
        return _UsersSection(repo: _repo);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Shared admin widget ──

class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: padding,
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF21262D)),
    ),
    child: child,
  );
}

class _AdminSectionHeader extends StatelessWidget {
  const _AdminSectionHeader({
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String title;
  final String subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: Color(0xFF7D89A8)),
              ),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AdminSectionHeader(
                title: 'Dashboard',
                subtitle: 'Panoramica globale della piattaforma',
              ),
              // KPI
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      label: 'Team totali',
                      value: '${teams.length}',
                      icon: Icons.groups_outlined,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      label: 'Utenti totali',
                      value: '$totalUsers',
                      icon: Icons.person_outlined,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      label: 'Team attivi',
                      value: '$activeTeams',
                      icon: Icons.verified_outlined,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KpiCard(
                      label: 'Utente admin',
                      value: '1',
                      icon: Icons.shield_outlined,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Recent teams
              _AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Team recenti',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (teams.isEmpty)
                      const Text(
                        'Nessun team creato.',
                        style: TextStyle(color: Color(0xFF7D89A8)),
                      )
                    else
                      ...teams
                          .take(5)
                          .map(
                            (t) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  _TeamAvatar(name: t.name),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.name,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          '${t.memberCount} membro/i · Creato ${DateFormat('dd/MM/yyyy').format(t.createdAt)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF7D89A8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.12),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: const Text(
                                      'Attivo',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF10B981),
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
            ],
          ),
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF21262D)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8)),
        ),
      ],
    ),
  );
}

// ────────────────────────────────────────────────
// Teams Section
// ────────────────────────────────────────────────

class _TeamsSection extends StatefulWidget {
  const _TeamsSection({required this.repo});
  final AdminRepository repo;
  @override
  State<_TeamsSection> createState() => _TeamsSectionState();
}

class _TeamsSectionState extends State<_TeamsSection> {
  AdminTeam? _selected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminTeam>>(
      stream: widget.repo.watchAllTeams(),
      builder: (context, snap) {
        final teams = snap.data ?? [];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // List
            SizedBox(
              width: _selected != null ? 380 : double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AdminSectionHeader(
                    title: 'Teams (${teams.length})',
                    subtitle: 'Tutti i team sulla piattaforma',
                    action: FilledButton.icon(
                      onPressed: () => _showCreateTeamDialog(context),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Nuovo team'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
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
                              color: isSel
                                  ? const Color(0xFF21262D)
                                  : const Color(0xFF161B22),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel
                                    ? const Color(
                                        0xFF3B82F6,
                                      ).withValues(alpha: 0.5)
                                    : const Color(0xFF21262D),
                              ),
                            ),
                            child: Row(
                              children: [
                                _TeamAvatar(name: t.name),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        '${t.memberCount} membro/i',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF7D89A8),
                                        ),
                                      ),
                                      Text(
                                        t.owner?.email ?? '—',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9AA0BC),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(
                                    Icons.more_horiz,
                                    size: 18,
                                    color: Color(0xFF7D89A8),
                                  ),
                                  color: const Color(0xFF161B22),
                                  onSelected: (v) async {
                                    if (v == 'delete') {
                                      final confirm = await _confirmDelete(
                                        context,
                                        'Elimina team "${t.name}"?',
                                      );
                                      if (confirm == true)
                                        await widget.repo.deleteTeam(t.id);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        'Elimina team',
                                        style: TextStyle(
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Detail panel
            if (_selected != null)
              Expanded(
                child: _TeamDetailPanel(
                  team: _selected!,
                  repo: widget.repo,
                  onClose: () => setState(() => _selected = null),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showCreateTeamDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _CreateTeamDialog(repo: widget.repo),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(message, style: const TextStyle(color: Colors.white)),
        content: const Text(
          'Questa azione è irreversibile.',
          style: TextStyle(color: Color(0xFF7D89A8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }
}

class _TeamDetailPanel extends StatefulWidget {
  const _TeamDetailPanel({
    required this.team,
    required this.repo,
    required this.onClose,
  });
  final AdminTeam team;
  final AdminRepository repo;
  final VoidCallback onClose;

  @override
  State<_TeamDetailPanel> createState() => _TeamDetailPanelState();
}

class _TeamDetailPanelState extends State<_TeamDetailPanel> {
  late Set<String> _enabledModules;
  late Set<String> _appliedPackageIds;
  late Future<List<ConfigurationPackage>> _packagesFuture;
  bool _savingModules = false;
  bool _savingPackages = false;

  Future<void> _reloadPackages() async {
    setState(() {
      _packagesFuture = widget.repo.listConfigurationPackages();
    });
  }

  @override
  void initState() {
    super.initState();
    _enabledModules = widget.team.enabledModules.toSet();
    _appliedPackageIds = widget.team.appliedPackageIds.toSet();
    _packagesFuture = widget.repo.listConfigurationPackages();
  }

  @override
  void didUpdateWidget(covariant _TeamDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.team.id != widget.team.id ||
        oldWidget.team.enabledModules.join('|') !=
            widget.team.enabledModules.join('|')) {
      _enabledModules = widget.team.enabledModules.toSet();
    }
    if (oldWidget.team.id != widget.team.id ||
        oldWidget.team.appliedPackageIds.join('|') !=
            widget.team.appliedPackageIds.join('|')) {
      _appliedPackageIds = widget.team.appliedPackageIds.toSet();
      _packagesFuture = widget.repo.listConfigurationPackages();
    }
  }

  Future<void> _toggleModule(String moduleId, bool enabled) async {
    setState(() {
      if (enabled) {
        _enabledModules.add(moduleId);
      } else {
        _enabledModules.remove(moduleId);
      }
      _savingModules = true;
    });
    try {
      await widget.repo.updateTeamModules(
        widget.team.id,
        _enabledModules.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Moduli team aggiornati')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _enabledModules = widget.team.enabledModules.toSet());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore aggiornamento moduli: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingModules = false);
    }
  }

  Future<void> _togglePackage(String packageId, bool enabled) async {
    setState(() {
      if (enabled) {
        _appliedPackageIds.add(packageId);
      } else {
        _appliedPackageIds.remove(packageId);
      }
      _savingPackages = true;
    });
    try {
      await widget.repo.applyConfigurationPackages(
        widget.team.id,
        _appliedPackageIds.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pacchetti configurazione applicati')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _appliedPackageIds = widget.team.appliedPackageIds.toSet(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore applicazione pacchetti: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingPackages = false);
    }
  }

  Future<void> _openPackageEditor({ConfigurationPackage? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfigurationPackageEditorDialog(
        repo: widget.repo,
        package: existing,
      ),
    );
    if (saved == true && mounted) {
      await _reloadPackages();
    }
  }

  Future<void> _deletePackage(ConfigurationPackage package) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(
          'Eliminare "${package.name}"?',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Il pacchetto verrà rimosso dal catalogo. I dati già copiati nei team resteranno invariati.',
          style: TextStyle(color: Color(0xFF9AA0BC)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.deleteConfigurationPackage(package.id);
      if (!mounted) return;
      await _reloadPackages();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pacchetto eliminato')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore eliminazione pacchetto: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF21262D))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
            child: Row(
              children: [
                _TeamAvatar(name: team.name, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'ID: ${team.id}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9AA0BC),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFF7D89A8),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF21262D), height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info
                  const Text(
                    'DETTAGLI',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF9AA0BC),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    label: 'Creato il',
                    value: DateFormat(
                      'dd/MM/yyyy HH:mm',
                    ).format(team.createdAt),
                  ),
                  _DetailRow(
                    label: 'Proprietario',
                    value: team.owner?.displayName ?? '—',
                  ),
                  _DetailRow(label: 'Membri', value: '${team.memberCount}'),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'MODULI EXTRA',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF9AA0BC),
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      if (_savingModules)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final category in _adminModuleCategories) ...[
                    _ModuleCategoryHeader(category: category),
                    const SizedBox(height: 8),
                    for (final module in _adminModuleSpecs.where(
                      (m) => m.categoryId == category.id,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ModuleToggleTile(
                          spec: module,
                          enabled: _enabledModules.contains(module.id),
                          busy: _savingModules,
                          onChanged: (value) => _toggleModule(module.id, value),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'PACCHETTI CONFIGURAZIONE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF9AA0BC),
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      if (_savingPackages)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _savingPackages
                            ? null
                            : () => _openPackageEditor(),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Nuovo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11161D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF21262D)),
                    ),
                    child: const Text(
                      'Usa i pacchetti per preconfigurare il team con moduli, ruoli e custom fields già pensati per un settore o un flusso operativo. La disattivazione rimuove l’associazione del pacchetto, ma non cancella automaticamente i campi e i ruoli già copiati nel team.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Color(0xFF9AA0BC),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<ConfigurationPackage>>(
                    future: _packagesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text(
                          'Errore caricamento pacchetti: ${snapshot.error}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final packages = snapshot.data!;
                      if (packages.isEmpty) {
                        return const Text(
                          'Nessun pacchetto disponibile.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9AA0BC),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final type
                              in ConfigurationPackageType.values) ...[
                            _PackageTypeHeader(type: type),
                            const SizedBox(height: 8),
                            for (final package in packages.where(
                              (item) => item.type == type,
                            ))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ConfigurationPackageTile(
                                  package: package,
                                  enabled: _appliedPackageIds.contains(
                                    package.id,
                                  ),
                                  busy: _savingPackages,
                                  onChanged: (value) =>
                                      _togglePackage(package.id, value),
                                  onEdit: () =>
                                      _openPackageEditor(existing: package),
                                  onDelete: () => _deletePackage(package),
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  // Members
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'MEMBRI',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF9AA0BC),
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _showAddMemberDialog(context),
                        child: const Row(
                          children: [
                            Icon(Icons.add, size: 14, color: Color(0xFF3B82F6)),
                            SizedBox(width: 4),
                            Text(
                              'Aggiungi',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF3B82F6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...team.members.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          _MemberChip(initials: m.initials),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.displayName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '${m.role} · ${m.email}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF7D89A8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (m.userId != team.ownerId)
                            IconButton(
                              onPressed: () => widget.repo.removeMember(
                                teamId: team.id,
                                userId: m.userId,
                              ),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 16,
                                color: Color(0xFFDC2626),
                              ),
                              tooltip: 'Rimuovi dal team',
                            ),
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
    );
  }

  void _showAddMemberDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _AddMemberDialog(teamId: widget.team.id, repo: widget.repo),
    );
  }
}

class _AdminModuleSpec {
  const _AdminModuleSpec({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String id;
  final String categoryId;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

class _AdminModuleCategory {
  const _AdminModuleCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

const _adminModuleCategories = [
  _AdminModuleCategory(
    id: 'general',
    title: 'Generale',
    description: 'Funzioni trasversali disponibili per qualunque realtà.',
    icon: Icons.tune_rounded,
    color: Color(0xFF22C55E),
  ),
  _AdminModuleCategory(
    id: 'communication',
    title: 'Comunicazione',
    description: 'Canali interni, collaborazione e relazione operativa.',
    icon: Icons.forum_rounded,
    color: Color(0xFF38BDF8),
  ),
  _AdminModuleCategory(
    id: 'automation_ai',
    title: 'AI & Automazione',
    description: 'Assistenti, automazioni e strumenti intelligenti.',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF8B5CF6),
  ),
  _AdminModuleCategory(
    id: 'investments',
    title: 'Investimenti',
    description: 'Moduli verticali per bandi, finanza agevolata e incentivi.',
    icon: Icons.travel_explore_rounded,
    color: Color(0xFFF59E0B),
  ),
  _AdminModuleCategory(
    id: 'payments',
    title: 'Pagamenti',
    description: 'Incassi in presenza, checkout e POS sul campo.',
    icon: Icons.contactless_rounded,
    color: Color(0xFF14B8A6),
  ),
];

const _adminModuleSpecs = [
  _AdminModuleSpec(
    id: TeamExtraModule.nexoraAi,
    categoryId: 'automation_ai',
    title: 'Nexora AI',
    description: 'Assistente AI e bubble contestuale nel sistema operativo.',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF8B5CF6),
  ),
  _AdminModuleSpec(
    id: TeamExtraModule.teamChat,
    categoryId: 'communication',
    title: 'Chat di team',
    description: 'Messaggi interni, chat dirette e spazi condivisi.',
    icon: Icons.forum_rounded,
    color: Color(0xFF38BDF8),
  ),
  _AdminModuleSpec(
    id: TeamExtraModule.integrations,
    categoryId: 'general',
    title: 'Integrazioni',
    description: 'Voce Integrazioni nelle impostazioni e servizi collegabili.',
    icon: Icons.hub_rounded,
    color: Color(0xFF22C55E),
  ),
  _AdminModuleSpec(
    id: TeamExtraModule.customBranding,
    categoryId: 'general',
    title: 'Branding personalizzato',
    description:
        'Abilita logo e colori custom del team in login e piattaforma.',
    icon: Icons.palette_rounded,
    color: Color(0xFF14B8A6),
  ),
  _AdminModuleSpec(
    id: TeamExtraModule.nexoraPos,
    categoryId: 'payments',
    title: 'Nexora POS',
    description:
        'Incassi in presenza, intents POS e ponte verso Tap to Pay / Stripe Terminal.',
    icon: Icons.contactless_rounded,
    color: Color(0xFF14B8A6),
  ),
  _AdminModuleSpec(
    id: TeamExtraModule.bandi,
    categoryId: 'investments',
    title: 'Bandi',
    description: 'Centro studi, ricerca bandi e matching con clienti.',
    icon: Icons.travel_explore_rounded,
    color: Color(0xFFF59E0B),
  ),
];

class _ModuleCategoryHeader extends StatelessWidget {
  const _ModuleCategoryHeader({required this.category});

  final _AdminModuleCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: category.color.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(category.icon, size: 15, color: category.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category.description,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    color: Color(0xFF9AA0BC),
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

class _ModuleToggleTile extends StatelessWidget {
  const _ModuleToggleTile({
    required this.spec,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final _AdminModuleSpec spec;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled
            ? spec.color.withValues(alpha: .13)
            : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled
              ? spec.color.withValues(alpha: .45)
              : const Color(0xFF21262D),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: spec.color.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(spec.icon, size: 18, color: spec.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.description,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    color: Color(0xFF9AA0BC),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: busy ? null : onChanged,
            activeThumbColor: spec.color,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF7D89A8)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF525D78),
            ),
          ),
        ),
      ],
    ),
  );
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AdminSectionHeader(
              title: 'Utenti (${users.length})',
              subtitle: 'Tutti gli account registrati con profilo',
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: users.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final u = users[i];
                  final uid = u['uid'] as String;
                  final name =
                      u['displayName'] as String? ?? uid.substring(0, 8);
                  final email = u['email'] as String? ?? '—';
                  final role = u['role'] as String? ?? '—';
                  final teamId = u['teamId'] as String?;
                  final isAdmin = role == 'superadmin';

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF21262D)),
                    ),
                    child: Row(
                      children: [
                        _MemberChip(
                          initials: name.isNotEmpty
                              ? name[0].toUpperCase()
                              : '?',
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (isAdmin) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFDC2626,
                                        ).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ADMIN',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFFDC2626),
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                email,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF7D89A8),
                                ),
                              ),
                              Text(
                                '$role${teamId != null ? " · Team: ${teamId.substring(0, 12)}..." : " · Nessun team"}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF9AA0BC),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Activity button
                        IconButton(
                          icon: const Icon(
                            Icons.bar_chart_outlined,
                            size: 16,
                            color: Color(0xFF7D89A8),
                          ),
                          tooltip: 'Attività',
                          onPressed: () => _showActivity(context, uid, name),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showActivity(
    BuildContext context,
    String uid,
    String name,
  ) async {
    final activity = await repo.getUserActivity(uid);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(
          'Attività di $name',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActivityRow(
              'Segnatempo inseriti',
              '${activity['timeTracksCount']}',
            ),
            _ActivityRow(
              'Ore totali tracciate',
              '${(activity['totalHours'] as double).toStringAsFixed(1)}h',
            ),
            _ActivityRow('Task creati', '${activity['tasksCount']}'),
            _ActivityRow('Fatture', '${activity['invoicesCount']}'),
            if (activity['lastActivity'] != null)
              _ActivityRow(
                'Ultima attività',
                DateFormat(
                  'dd/MM/yyyy',
                ).format(activity['lastActivity'] as DateTime),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF525D78)),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

// ────────────────────────────────────────────────
// Shared admin widgets
// ────────────────────────────────────────────────

class _TeamAvatar extends StatelessWidget {
  const _TeamAvatar({required this.name, this.size = 36});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final init = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.25),
        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
        border: Border.all(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
        ),
      ),
      child: Center(
        child: Text(
          init,
          style: TextStyle(
            fontSize: size * 0.38,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF3B82F6),
          ),
        ),
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({required this.initials});
  final String initials;
  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Color(0xFF21262D),
    ),
    child: Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF525D78),
        ),
      ),
    ),
  );
}

class _PackageTypeHeader extends StatelessWidget {
  const _PackageTypeHeader({required this.type});

  final ConfigurationPackageType type;

  @override
  Widget build(BuildContext context) {
    final color = type == ConfigurationPackageType.sector
        ? const Color(0xFFF59E0B)
        : const Color(0xFF14B8A6);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _ConfigurationPackageTile extends StatelessWidget {
  const _ConfigurationPackageTile({
    required this.package,
    required this.enabled,
    required this.busy,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final ConfigurationPackage package;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = _packageColor(package.color);
    final fieldsByModule = <String, int>{};
    for (final field in package.customFieldDefinitions) {
      fieldsByModule[field.module.label] =
          (fieldsByModule[field.module.label] ?? 0) + 1;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? color.withValues(alpha: .12) : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled
              ? color.withValues(alpha: .42)
              : const Color(0xFF21262D),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_packageIcon(package.icon), size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      package.description,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: Color(0xFF9AA0BC),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                onChanged: busy ? null : onChanged,
                activeThumbColor: color,
                activeTrackColor: color.withValues(alpha: .4),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (package.enabledModules.isNotEmpty)
                _PackageMetricChip(
                  label: '${package.enabledModules.length} moduli',
                  color: color,
                ),
              if (package.teamRoles.isNotEmpty)
                _PackageMetricChip(
                  label: '${package.teamRoles.length} ruoli',
                  color: color,
                ),
              if (package.customFieldDefinitions.isNotEmpty)
                _PackageMetricChip(
                  label: '${package.customFieldDefinitions.length} campi',
                  color: color,
                ),
              if (package.system)
                _PackageMetricChip(label: 'System', color: color),
            ],
          ),
          if (fieldsByModule.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: fieldsByModule.entries
                  .map(
                    (entry) => _PackageMetricChip(
                      label: '${entry.key} ${entry.value}',
                      color: const Color(0xFF64748B),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Modifica'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: busy ? null : onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Color(0xFFDC2626),
                ),
                label: const Text(
                  'Elimina',
                  style: TextStyle(color: Color(0xFFDC2626)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PackageMetricChip extends StatelessWidget {
  const _PackageMetricChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

Color _packageColor(String raw) {
  final value = raw.trim().replaceFirst('#', '');
  if (value.length == 6) {
    return Color(int.parse('FF$value', radix: 16));
  }
  return const Color(0xFF22C55E);
}

IconData _packageIcon(String raw) {
  switch (raw.trim()) {
    case 'construction':
      return Icons.construction_rounded;
    case 'support_agent':
      return Icons.support_agent_rounded;
    case 'analytics':
      return Icons.analytics_rounded;
    case 'home_repair_service':
      return Icons.home_repair_service_rounded;
    case 'inventory_2':
      return Icons.inventory_2_rounded;
    default:
      return Icons.widgets_rounded;
  }
}

class _ConfigurationPackageEditorDialog extends StatefulWidget {
  const _ConfigurationPackageEditorDialog({required this.repo, this.package});

  final AdminRepository repo;
  final ConfigurationPackage? package;

  @override
  State<_ConfigurationPackageEditorDialog> createState() =>
      _ConfigurationPackageEditorDialogState();
}

class _ConfigurationPackageEditorDialogState
    extends State<_ConfigurationPackageEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _iconCtrl;
  late ConfigurationPackageType _type;
  late Set<String> _modules;
  late List<String> _roles;
  late List<TeamCustomFieldDefinition> _fields;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.package;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _descriptionCtrl = TextEditingController(text: existing?.description ?? '');
    _colorCtrl = TextEditingController(text: existing?.color ?? '#22C55E');
    _iconCtrl = TextEditingController(text: existing?.icon ?? 'widgets');
    _type = existing?.type ?? ConfigurationPackageType.customFields;
    _modules = {...?existing?.enabledModules};
    _roles = [...?existing?.teamRoles];
    _fields = [...?existing?.customFieldDefinitions];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _colorCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Inserisci il nome del pacchetto.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.saveConfigurationPackage(
        ConfigurationPackage(
          id: widget.package?.id ?? '',
          type: _type,
          name: name,
          description: _descriptionCtrl.text.trim(),
          icon: _iconCtrl.text.trim().isEmpty
              ? 'widgets'
              : _iconCtrl.text.trim(),
          color: _colorCtrl.text.trim().isEmpty
              ? '#22C55E'
              : _colorCtrl.text.trim(),
          enabledModules: _modules.toList(),
          teamRoles: _roles,
          customFieldDefinitions: _fields,
          system: widget.package?.system ?? false,
          active: true,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editRole({String? existing}) async {
    final controller = TextEditingController(text: existing ?? '');
    final role = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Text(
          existing == null ? 'Nuovo ruolo' : 'Modifica ruolo',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Ruolo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (role == null || role.trim().isEmpty) return;
    setState(() {
      if (existing != null) {
        _roles.remove(existing);
      }
      if (!_roles.any((item) => item.toLowerCase() == role.toLowerCase())) {
        _roles.add(role);
      }
      _roles.sort();
    });
  }

  Future<void> _editField({TeamCustomFieldDefinition? existing}) async {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final maxLengthCtrl = TextEditingController(
      text: (existing?.maxLength ?? 255).toString(),
    );
    final optionsCtrl = TextEditingController(
      text: existing?.options.join('\n') ?? '',
    );
    CustomFieldModule module = existing?.module ?? CustomFieldModule.companies;
    CustomFieldType type = existing?.type ?? CustomFieldType.text;

    final result = await showDialog<TeamCustomFieldDefinition>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: Text(
            existing == null ? 'Nuovo campo del pacchetto' : 'Modifica campo',
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<CustomFieldModule>(
                  initialValue: module,
                  decoration: const InputDecoration(labelText: 'Modulo'),
                  items: CustomFieldModule.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setModalState(() => module = value ?? module),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: 'Etichetta'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CustomFieldType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipologia'),
                  items: CustomFieldType.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setModalState(() => type = value ?? type),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxLengthCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Lunghezza massima',
                  ),
                ),
                if (type == CustomFieldType.select) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: optionsCtrl,
                    minLines: 4,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Opzioni (una per riga)',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                final label = labelCtrl.text.trim();
                if (label.isEmpty) return;
                Navigator.pop(
                  ctx,
                  TeamCustomFieldDefinition(
                    id:
                        existing?.id ??
                        'pkg-cf-${DateTime.now().microsecondsSinceEpoch}',
                    module: module,
                    label: label,
                    type: type,
                    maxLength:
                        int.tryParse(
                          maxLengthCtrl.text.trim(),
                        )?.clamp(1, 5000) ??
                        255,
                    options: optionsCtrl.text
                        .split('\n')
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty)
                        .toList(),
                  ),
                );
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    labelCtrl.dispose();
    maxLengthCtrl.dispose();
    optionsCtrl.dispose();

    if (result == null) return;
    setState(() {
      final index = _fields.indexWhere((item) => item.id == result.id);
      if (index >= 0) {
        _fields[index] = result;
      } else {
        _fields.add(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F1117),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.package == null
                    ? 'Nuovo pacchetto configurazione'
                    : 'Modifica pacchetto',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nome pacchetto',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child:
                                DropdownButtonFormField<
                                  ConfigurationPackageType
                                >(
                                  initialValue: _type,
                                  decoration: const InputDecoration(
                                    labelText: 'Tipologia',
                                  ),
                                  items: ConfigurationPackageType.values
                                      .map(
                                        (item) => DropdownMenuItem(
                                          value: item,
                                          child: Text(item.label),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) => setState(
                                    () => _type =
                                        value ??
                                        ConfigurationPackageType.customFields,
                                  ),
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descriptionCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Descrizione',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _iconCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Icona (construction, analytics...)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _colorCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Colore hex',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Moduli inclusi',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _adminModuleSpecs
                            .map(
                              (spec) => FilterChip(
                                label: Text(spec.title),
                                selected: _modules.contains(spec.id),
                                onSelected: (value) {
                                  setState(() {
                                    if (value) {
                                      _modules.add(spec.id);
                                    } else {
                                      _modules.remove(spec.id);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Ruoli suggeriti',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _editRole(),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Aggiungi ruolo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _roles
                            .map(
                              (role) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF161B22),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFF21262D),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      role,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => _editRole(existing: role),
                                      child: const Icon(
                                        Icons.edit_outlined,
                                        size: 14,
                                        color: Color(0xFF9AA0BC),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () =>
                                          setState(() => _roles.remove(role)),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 14,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Custom fields del pacchetto',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _editField(),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Nuovo campo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_fields.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF21262D)),
                          ),
                          child: const Text(
                            'Nessun custom field nel pacchetto.',
                            style: TextStyle(color: Color(0xFF9AA0BC)),
                          ),
                        )
                      else
                        Column(
                          children: _fields
                              .map(
                                (field) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF161B22),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFF21262D),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              field.label,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${field.module.label} · ${field.type.label}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF9AA0BC),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            _editField(existing: field),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: Color(0xFF9AA0BC),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => setState(
                                          () => _fields.removeWhere(
                                            (item) => item.id == field.id,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFDC2626)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Salva pacchetto'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dialogs ──

class _CreateTeamDialog extends StatefulWidget {
  const _CreateTeamDialog({required this.repo});
  final AdminRepository repo;
  @override
  State<_CreateTeamDialog> createState() => _CreateTeamDialogState();
}

class _CreateTeamDialogState extends State<_CreateTeamDialog> {
  final _teamNameCtrl = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _ownerPassCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    _ownerEmailCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.createTeam(
        name: _teamNameCtrl.text.trim(),
        ownerEmail: _ownerEmailCtrl.text.trim(),
        ownerDisplayName: _ownerNameCtrl.text.trim(),
        ownerRole: '', // il primo utente è sempre owner, nessun ruolo
        ownerPassword: _ownerPassCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF161B22),
    title: const Text(
      'Crea nuovo team',
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AdminTextField(ctrl: _teamNameCtrl, label: 'Nome team *'),
          const SizedBox(height: 12),
          const Text(
            'Proprietario del team',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF7D89A8),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Il primo utente è sempre Owner — nessun ruolo aggiuntivo.',
            style: TextStyle(fontSize: 11, color: Color(0xFF525D78)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AdminTextField(ctrl: _ownerEmailCtrl, label: 'Email *'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AdminTextField(
                  ctrl: _ownerPassCtrl,
                  label: 'Password *',
                  obscure: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AdminTextField(ctrl: _ownerNameCtrl, label: 'Nome completo'),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(
          'Annulla',
          style: TextStyle(color: Color(0xFF7D89A8)),
        ),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
        child: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Crea team'),
      ),
    ],
  );
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({required this.teamId, required this.repo});
  final String teamId;
  final AdminRepository repo;
  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _selectedRole;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedRole == null) {
      setState(() => _error = 'Seleziona un ruolo.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
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
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF161B22),
    title: const Text(
      'Aggiungi membro',
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
    ),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _AdminTextField(ctrl: _emailCtrl, label: 'Email *'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AdminTextField(
                  ctrl: _passCtrl,
                  label: 'Password *',
                  obscure: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AdminTextField(ctrl: _nameCtrl, label: 'Nome completo'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RoleDropdown(
                  value: _selectedRole,
                  onChanged: (v) => setState(() => _selectedRole = v),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(
          'Annulla',
          style: TextStyle(color: Color(0xFF7D89A8)),
        ),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
        child: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Aggiungi'),
      ),
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
      hint: const Text(
        'Ruolo *',
        style: TextStyle(fontSize: 12, color: Color(0xFF7D89A8)),
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF0D1117),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF21262D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF21262D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3B82F6)),
        ),
      ),
      dropdownColor: const Color(0xFF161B22),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      items: GussoniRoles.all
          .map((r) => DropdownMenuItem(value: r, child: Text(r)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _AdminTextField extends StatelessWidget {
  const _AdminTextField({
    required this.ctrl,
    required this.label,
    this.obscure = false,
  });
  final TextEditingController ctrl;
  final String label;
  final bool obscure;
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    obscureText: obscure,
    style: const TextStyle(color: Colors.white, fontSize: 13),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF7D89A8), fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF0D1117),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF21262D)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF21262D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF3B82F6)),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  );
}
