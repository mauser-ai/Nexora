import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:gussoni_crm/data/api_client.dart';
import 'package:gussoni_crm/data/api_workspace_repository.dart';
import 'package:gussoni_crm/data/team_repository.dart';
import 'package:gussoni_crm/gussoni/screens/segnatempo_screen.dart';
import 'package:gussoni_crm/models/domain_models.dart';

class NoRequestsClient extends Fake implements ApiClient {
  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async =>
      throw StateError('Unexpected request: $path');
}

const members = [
  TeamMember(
    userId: 'owner',
    email: '',
    displayName: 'Owner',
    role: '',
    status: 'active',
  ),
  TeamMember(
    userId: 'claudia',
    email: '',
    displayName: 'Claudia',
    role: '',
    status: 'active',
  ),
  TeamMember(
    userId: 'nicolo',
    email: '',
    displayName: 'Nicolo',
    role: '',
    status: 'active',
  ),
];

TimeTrack todayTrack(String user) {
  final now = DateTime.now();
  return TimeTrack(
    id: user,
    taskId: '',
    name: '$user record',
    companyId: '',
    projectId: '',
    startAt: DateTime(now.year, now.month, now.day, 9),
    endAt: DateTime(now.year, now.month, now.day, 10),
    userId: user,
  );
}

Widget screen() => MaterialApp(
  home: Scaffold(
    body: SegantempoGussoniScreen(
      workspace: WorkspaceSnapshot.empty.copyWith(
        timeTracks: [todayTrack('claudia'), todayTrack('nicolo')],
      ),
      userId: 'owner',
      repository: ApiWorkspaceRepository(client: NoRequestsClient()),
      teamInfo: const TeamInfo(
        id: 'team',
        name: 'Team',
        ownerId: 'owner',
        members: members,
      ),
      onAddTimeTrack: ({date, track}) {},
      desktopTimers: const [],
      onStartTimer: () {},
      onStopTimer: (_) {},
      onOpenPendingTimer: (_) {},
      onDiscardPendingTimer: (_) {},
    ),
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  testWidgets(
    'team and colleague selections show shared SQL records without subscriptions',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.text('Tutto il team'), findsOneWidget);
      expect(find.text('claudia record'), findsOneWidget);
      expect(find.text('nicolo record'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nicolo').last);
      await tester.pumpAndSettle();
      expect(find.text('nicolo record'), findsOneWidget);
      expect(find.text('claudia record'), findsNothing);
    },
  );

  testWidgets('mobile starts from the same team records', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('claudia record'), findsOneWidget);
    expect(find.text('nicolo record'), findsOneWidget);
  });
}
