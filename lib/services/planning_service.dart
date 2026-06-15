import '../models/domain_models.dart';

class PlanningResult {
  const PlanningResult({required this.slots, required this.unallocatedHours});

  final List<TimelineSlot> slots;
  final double unallocatedHours;
}

class PlanningService {
  const PlanningService();
  static const double _dailyPlanningCapHours = 6.0;

  PlanningResult distributeTask({
    required WorkTask task,
    required DateTime startDate,
    required DateTime endDate,
    required List<UserAvailability> weeklyAvailability,
    required Set<DateTime> blockedDates,
    required Map<DateTime, double> alreadyPlannedHours,
  }) {
    final slots = <TimelineSlot>[];
    final availabilityByWeekday = {
      for (final entry in weeklyAvailability) entry.weekday: entry,
    };

    var remainingMinutes = (task.remainingHours * 60).round();
    var cursor = DateTime(startDate.year, startDate.month, startDate.day);
    var safetyCounter = 0;
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);
    final candidateDays = <({DateTime day, double consumed, double free})>[];

    while (safetyCounter < 366 && !cursor.isAfter(normalizedEnd)) {
      final availability = availabilityByWeekday[cursor.weekday];
      final dayKey = DateTime(cursor.year, cursor.month, cursor.day);

      if (!blockedDates.contains(dayKey) &&
          availability != null &&
          !availability.isOff) {
        final consumed = alreadyPlannedHours[dayKey] ?? 0;
        final dayCapacity = availability.hours <= 0
            ? _dailyPlanningCapHours
            : availability.hours.clamp(0, _dailyPlanningCapHours).toDouble();
        final freeHours = (dayCapacity - consumed).clamp(0, 24).toDouble();
        if (freeHours > 0) {
          candidateDays.add((day: dayKey, consumed: consumed, free: freeHours));
        }
      }

      cursor = cursor.add(const Duration(days: 1));
      safetyCounter += 1;
    }

    if (candidateDays.isEmpty || remainingMinutes <= 0) {
      return PlanningResult(
        slots: slots,
        unallocatedHours: double.parse(
          (remainingMinutes / 60.0).toStringAsFixed(2),
        ),
      );
    }

    for (var i = 0; i < candidateDays.length && remainingMinutes > 0; i++) {
      final item = candidateDays[i];
      final freeMinutes = (item.free * 60).floor();
      if (freeMinutes <= 0) {
        continue;
      }
      final remainingDays = candidateDays.length - i;
      final targetMinutes = (remainingMinutes / remainingDays).ceil();
      final allocatedMinutes = remainingDays == 1
          ? (remainingMinutes < freeMinutes ? remainingMinutes : freeMinutes)
          : (targetMinutes < freeMinutes ? targetMinutes : freeMinutes);
      if (allocatedMinutes <= 0) {
        continue;
      }
      final allocated = allocatedMinutes / 60.0;
      slots.add(
        TimelineSlot(
          id: '${task.id}-${item.day.toIso8601String()}',
          taskId: task.id,
          date: item.day,
          plannedHours: allocated,
          startHour: 9 + item.consumed,
        ),
      );
      alreadyPlannedHours[item.day] = item.consumed + allocated;
      remainingMinutes -= allocatedMinutes;
    }

    // Second pass: if there is still remainder, fill any residual daily capacity.
    if (remainingMinutes > 0) {
      for (final item in candidateDays) {
        if (remainingMinutes <= 0) {
          break;
        }
        final already = alreadyPlannedHours[item.day] ?? item.consumed;
        final residualHours = (item.consumed + item.free - already).clamp(
          0,
          _dailyPlanningCapHours,
        );
        final residualMinutes = (residualHours * 60).floor();
        if (residualMinutes <= 0) {
          continue;
        }
        final allocatedMinutes = remainingMinutes < residualMinutes
            ? remainingMinutes
            : residualMinutes;
        final allocated = allocatedMinutes / 60.0;
        final existingIndex = slots.indexWhere((slot) => slot.date == item.day);
        if (existingIndex >= 0) {
          final current = slots[existingIndex];
          slots[existingIndex] = current.copyWith(
            plannedHours: current.plannedHours + allocated,
          );
        } else {
          slots.add(
            TimelineSlot(
              id: '${task.id}-${item.day.toIso8601String()}',
              taskId: task.id,
              date: item.day,
              plannedHours: allocated,
              startHour: 9 + already,
            ),
          );
        }
        alreadyPlannedHours[item.day] = already + allocated;
        remainingMinutes -= allocatedMinutes;
      }
    }

    return PlanningResult(
      slots: slots,
      unallocatedHours: double.parse(
        (remainingMinutes / 60.0).toStringAsFixed(2),
      ),
    );
  }

  String pseudocode() {
    return '''
function distributeTask(task, userAvailability, existingSlots):
  remainingHours = task.estimatedHours - task.loggedHours
  currentDay = today()
  allocatedSlots = []

  while remainingHours > 0:
    dayRule = userAvailability[currentDay.weekday]

    if dayRule.isOff == true or currentDay in vacationRanges:
      currentDay = currentDay + 1 day
      continue

    plannedHoursToday = sum(existingSlots on currentDay)
    freeHoursToday = max(dayRule.hours - plannedHoursToday, 0)

    if freeHoursToday > 0:
      hoursForThisSlot = min(freeHoursToday, remainingHours)
      allocatedSlots.append(
        slot(taskId=task.id, date=currentDay, plannedHours=hoursForThisSlot)
      )
      remainingHours = remainingHours - hoursForThisSlot

    currentDay = currentDay + 1 day

  return {
    slots: allocatedSlots,
    unallocatedHours: remainingHours
  }
''';
  }
}
