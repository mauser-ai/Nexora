import 'package:flutter_test/flutter_test.dart';
import 'package:gussoni_crm/models/domain_models.dart';
import 'package:gussoni_crm/models/time_track_filters.dart';

TimeTrack track(String id, String userId) => TimeTrack(
  id: id,
  taskId: '',
  name: id,
  companyId: '',
  projectId: '',
  startAt: DateTime(2026, 11, 11, 9),
  endAt: DateTime(2026, 11, 11, 10),
  userId: userId,
);

void main() {
  final records = [track('a', 'claudia'), track('b', 'nicolo'), track('c', '')];

  test('team view uses every authorized MySQL record', () {
    expect(timeTracksForUser(records, null).map((t) => t.id), ['a', 'b', 'c']);
  });

  test(
    'colleague selection filters the shared snapshot without a member cache',
    () {
      expect(timeTracksForUser(records, 'nicolo').map((t) => t.id), ['b']);
    },
  );

  test('unknown colleague does not reveal another user records', () {
    expect(timeTracksForUser(records, 'missing'), isEmpty);
  });

  test('legacy rows are assigned only with an explicit owner fallback', () {
    expect(timeTracksForUser(records, 'claudia').map((t) => t.id), ['a']);
    expect(
      timeTracksForUser(
        records,
        'claudia',
        legacyOwnerId: 'claudia',
      ).map((t) => t.id),
      ['a', 'c'],
    );
    expect(
      timeTracksForUser(
        records,
        'nicolo',
        legacyOwnerId: 'claudia',
      ).map((t) => t.id),
      ['b'],
    );
  });

  test('newly polled records are visible without a separate subscription', () {
    final updated = [...records, track('new', 'nicolo')];
    expect(timeTracksForUser(updated, 'nicolo').map((t) => t.id), ['b', 'new']);
  });

  test('filter result can be sorted without changing the shared snapshot', () {
    final filtered = timeTracksForUser(records, null)..clear();
    expect(filtered, isEmpty);
    expect(records.length, 3);
  });
}
