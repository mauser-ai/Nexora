import '../../brand_config.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/firestore_workspace_repository.dart';
import '../../models/domain_models.dart';

// ────────────────────────────────────────────────
// CaricoCard – vista workload giornaliero
// Mostra per ogni giorno: ore pianificate vs disponibili
// con task assegnati e stato avanzamento
// ────────────────────────────────────────────────

class CaricoCard extends StatefulWidget {
  const CaricoCard({super.key, required this.workspace});
  final WorkspaceSnapshot workspace;

  @override
  State<CaricoCard> createState() => _CaricoCardState();
}

class _CaricoCardState extends State<CaricoCard> {
  late DateTime _weekStart;
  int _weeksAhead = 2; // mostra current + 2 settimane (21 giorni)

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
  }

  DateTime _mondayOf(DateTime d) {
    final diff = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  // Ore disponibili per un giorno (da availability)
  double _availableHours(DateTime day) {
    if (_isVacation(day)) return 0;
    final avail = widget.workspace.availability.firstWhere(
      (a) => a.weekday == day.weekday,
      orElse: () => const UserAvailability(weekday: 0, hours: 0, isOff: true),
    );
    if (avail.isOff) return 0;
    return avail.hours > 0 ? avail.hours : 8.0;
  }

  // Ore pianificate per un giorno (da timelineSlots)
  double _plannedHours(DateTime day) {
    final norm = DateTime(day.year, day.month, day.day);
    return widget.workspace.plannedSlots
        .where((s) {
          final d = DateTime(s.date.year, s.date.month, s.date.day);
          return d == norm;
        })
        .fold(0.0, (sum, s) => sum + s.plannedHours);
  }

  // Task pianificati per un giorno
  List<WorkTask> _tasksForDay(DateTime day) {
    final norm = DateTime(day.year, day.month, day.day);
    final taskIds = widget.workspace.plannedSlots
        .where((s) {
          final d = DateTime(s.date.year, s.date.month, s.date.day);
          return d == norm;
        })
        .map((s) => s.taskId)
        .toSet();
    return widget.workspace.tasks
        .where((t) => taskIds.contains(t.id))
        .toList();
  }

  bool _isVacation(DateTime day) {
    return widget.workspace.vacations.any((v) => v.includes(day));
  }

  bool _isWeekend(DateTime day) =>
      day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  Color _barColor(double planned, double available) {
    if (available <= 0) return const Color(0xFFE9E5DF);
    final ratio = planned / available;
    if (ratio >= 1.0) return const Color(0xFFA8332C); // sovraccarico
    if (ratio >= 0.8) return const Color(0xFFB97D10); // quasi pieno
    return GussoniBrand.primary; // ok
  }

  @override
  Widget build(BuildContext context) {
    // Genera i giorni lavorativi delle settimane da visualizzare
    final totalDays = 7 * (_weeksAhead + 1);
    final days = List.generate(totalDays, (i) => _weekStart.add(Duration(days: i)));

    // Totali aggregati
    final totalPlanned = days.fold(0.0, (s, d) => s + _plannedHours(d));
    final totalAvailable = days.fold(0.0, (s, d) => s + _availableHours(d));
    final overloadedDays = days.where((d) => _plannedHours(d) > _availableHours(d) && _availableHours(d) > 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header KPI ──
        Row(children: [
          _KpiPill(label: 'Pianificate', value: '${totalPlanned.toStringAsFixed(1)}h', color: GussoniBrand.primary),
          const SizedBox(width: 10),
          _KpiPill(label: 'Disponibili', value: '${totalAvailable.toStringAsFixed(1)}h', color: const Color(0xFF4A6B8A)),
          const SizedBox(width: 10),
          if (overloadedDays > 0) _KpiPill(label: 'Giorni sovraccarichi', value: '$overloadedDays', color: const Color(0xFFA8332C)),
          const Spacer(),
          // Navigazione settimane
          _NavBtn(icon: Icons.chevron_left, onTap: () => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)))),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => setState(() => _weekStart = _mondayOf(DateTime.now())),
            child: const Text('Oggi'),
          ),
          const SizedBox(width: 4),
          _NavBtn(icon: Icons.chevron_right, onTap: () => setState(() => _weekStart = _weekStart.add(const Duration(days: 7)))),
          const SizedBox(width: 12),
          // Mostra N settimane
          _WeekSelector(current: _weeksAhead + 1, onChanged: (w) => setState(() => _weeksAhead = w - 1)),
        ]),
        const SizedBox(height: 16),

        // ── Grid settimane ──
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: List.generate(_weeksAhead + 1, (weekIndex) {
                final weekDays = days.sublist(weekIndex * 7, (weekIndex + 1) * 7);
                final weekLabel = 'Settimana del ${DateFormat('d MMM', 'it_IT').format(weekDays[0])}';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(weekLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF8C8478))),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: weekDays.map((day) {
                        final planned = _plannedHours(day);
                        final available = _availableHours(day);
                        final tasks = _tasksForDay(day);
                        final isWe = _isWeekend(day);
                        final isVac = _isVacation(day);
                        final today = _isToday(day);
                        final barColor = _barColor(planned, available);
                        final ratio = available > 0 ? (planned / available).clamp(0.0, 1.0) : 0.0;

                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isWe || isVac ? const Color(0xFFFAF9F7) : const Color(0xFFFFFFFF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: today ? GussoniBrand.primary : const Color(0xFFE9E5DF), width: today ? 2 : 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Day header
                                Text(
                                  DateFormat('EEE', 'it_IT').format(day).toUpperCase(),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: today ? GussoniBrand.primary : const Color(0xFFC1B8AB), letterSpacing: 0.5),
                                ),
                                Text(
                                  DateFormat('d', 'it_IT').format(day),
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: today ? GussoniBrand.primary : (isWe || isVac ? const Color(0xFFE9E5DF) : const Color(0xFF1C1D1F))),
                                ),
                                const SizedBox(height: 6),
                                if (isWe) ...[
                                  const Text('Weekend', style: TextStyle(fontSize: 10, color: Color(0xFFE9E5DF))),
                                ] else if (isVac) ...[
                                  const Text('Ferie', style: TextStyle(fontSize: 10, color: Color(0xFFC1B8AB))),
                                ] else ...[
                                  // Progress bar
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: 5,
                                      backgroundColor: const Color(0xFFE9E5DF),
                                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    planned > 0 ? '${planned.toStringAsFixed(1)}h / ${available.toStringAsFixed(0)}h' : '${available.toStringAsFixed(0)}h libere',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: planned > 0 ? barColor : const Color(0xFFC1B8AB)),
                                  ),
                                  if (tasks.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    ...tasks.take(3).map((t) {
                                      final company = widget.workspace.companies.where((c) => c.id == t.companyId).firstOrNull;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 3),
                                        child: Row(children: [
                                          Container(
                                            width: 5, height: 5,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: t.status == TaskStatus.done ? GussoniBrand.primary : const Color(0xFF4A6B8A),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(child: Text(
                                            company != null ? '${company.name} · ${t.name}' : t.name,
                                            style: const TextStyle(fontSize: 9, color: Color(0xFF54595F)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          )),
                                        ]),
                                      );
                                    }),
                                    if (tasks.length > 3)
                                      Text('+${tasks.length - 3} altri', style: const TextStyle(fontSize: 9, color: Color(0xFFC1B8AB))),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ]),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiPill extends StatelessWidget {
  const _KpiPill({required this.label, required this.value, required this.color});
  final String label; final String value; final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
    ]),
  );
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onTap});
  final IconData icon; final VoidCallback onTap;
  @override Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE9E5DF)), color: Colors.white),
      child: Icon(icon, size: 18, color: const Color(0xFF54595F)),
    ),
  );
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector({required this.current, required this.onChanged});
  final int current; final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    const Text('Settimane:', style: TextStyle(fontSize: 12, color: Color(0xFF8C8478))),
    const SizedBox(width: 6),
    ...[1, 2, 3].map((w) => GestureDetector(
      onTap: () => onChanged(w),
      child: Container(
        width: 28, height: 28,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: current == w ? GussoniBrand.primary : const Color(0xFFF6F4F1),
        ),
        child: Center(child: Text('$w', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: current == w ? Colors.white : const Color(0xFF54595F)))),
      ),
    )),
  ]);
}
