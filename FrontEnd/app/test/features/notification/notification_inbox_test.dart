import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/notification_api_client.dart';
import 'package:wadadak/features/notification/notification_bell.dart';
import 'package:wadadak/features/notification/notification_inbox_screen.dart';
import 'package:wadadak/routes.dart';

import '../../fakes.dart';

/// F3 알림함 · A2 종 아이콘. 홈 대신 종 아이콘만 있는 화면, B1 대신 코스 ID만 보이는 화면을 쓴다.
void main() {
  final now = DateTime.utc(2026, 11, 4, 3); // 서울 11월 4일 정오
  late FakeNotificationApi api;

  NotificationItem item(String id, {Duration ago = const Duration(minutes: 12), bool read = false, String? courseId}) =>
      NotificationItem(
        id: id,
        kind: 'COURSE_EXPIRING_SOON',
        title: '내 코스 만료 임박',
        body: '‘$id’ 코스가 7일 뒤 만료돼요.',
        data: {'type': 'COURSE_EXPIRING_SOON', 'courseId': courseId ?? 'c-$id'},
        createdAt: now.subtract(ago),
        read: read,
      );

  setUp(() => api = FakeNotificationApi());

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: Routes.home,
      routes: [
        GoRoute(
          path: Routes.home,
          builder: (_, _) => const Scaffold(body: SafeArea(child: Row(children: [Text('A2'), NotificationBell()]))),
          routes: [GoRoute(path: 'notifications', builder: (_, _) => NotificationInboxScreen(now: () => now))],
        ),
        GoRoute(
          path: '/course/:courseId',
          builder: (_, state) => Scaffold(body: Text('B1 ${state.pathParameters['courseId']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [notificationApiClientProvider.overrideWithValue(api)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openInbox(WidgetTester tester) async {
    await tester.tap(find.byType(NotificationBell));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    GoRouter.of(tester.element(find.byType(Scaffold).last)).pop();
    await tester.pumpAndSettle();
  }

  final dot = find.byKey(const ValueKey('notification-bell-dot'));

  testWidgets('the bell shows a dot while something is unread and opens the inbox', (tester) async {
    api.inboxItems.addAll([item('한강', courseId: 'c-1'), item('정릉', ago: const Duration(days: 2), read: true)]);
    await pumpHome(tester);
    expect(dot, findsOneWidget);
    expect(find.bySemanticsLabel('알림, 읽지 않은 알림 1개'), findsOneWidget);

    await openInbox(tester);

    expect(find.text('알림'), findsOneWidget);
    expect(find.text('최근 30일'), findsOneWidget);
    expect(find.text('읽지 않음 1'), findsOneWidget);
    expect(find.text('‘한강’ 코스가 7일 뒤 만료돼요.'), findsOneWidget);
    expect(find.text('12분 전'), findsOneWidget);
    expect(find.text('2일 전'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-한강')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-정릉')), findsNothing);
    expect(find.text('코스 만료 알림은 내가 등록한 코스에만 보내요.'), findsOneWidget);
  });

  testWidgets('tapping a notification marks it read and opens B1', (tester) async {
    api.inboxItems.add(item('한강', courseId: 'c-1'));
    await pumpHome(tester);
    await openInbox(tester);

    await tester.tap(find.text('‘한강’ 코스가 7일 뒤 만료돼요.'));
    await tester.pumpAndSettle();

    expect(api.markedRead, ['한강']);
    expect(find.text('B1 c-1'), findsOneWidget);

    // B1 · 알림함을 닫고 홈으로 오면 점이 없다
    await back(tester);
    expect(find.byKey(const ValueKey('unread-한강')), findsNothing);
    expect(find.text('읽지 않음 1'), findsNothing);
    await back(tester);
    expect(find.text('A2'), findsOneWidget);
    expect(dot, findsNothing);
  });

  testWidgets('a read notification is not sent again but still opens B1', (tester) async {
    api.inboxItems.add(item('한강', read: true, courseId: 'c-1'));
    await pumpHome(tester);
    await openInbox(tester);

    await tester.tap(find.text('‘한강’ 코스가 7일 뒤 만료돼요.'));
    await tester.pumpAndSettle();

    expect(api.markedRead, isEmpty);
    expect(find.text('B1 c-1'), findsOneWidget);
  });

  testWidgets('B1 still opens when saving read fails', (tester) async {
    api
      ..inboxItems.add(item('한강', courseId: 'c-1'))
      ..failRead = true;
    await pumpHome(tester);
    await openInbox(tester);

    await tester.tap(find.text('‘한강’ 코스가 7일 뒤 만료돼요.'));
    await tester.pumpAndSettle();

    expect(find.text('B1 c-1'), findsOneWidget);
  });

  testWidgets('read all clears every dot', (tester) async {
    api.inboxItems.addAll([item('한강'), item('정릉', ago: const Duration(hours: 3))]);
    await pumpHome(tester);
    await openInbox(tester);
    expect(find.text('읽지 않음 2'), findsOneWidget);

    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();

    expect(api.markedAllRead, 1);
    expect(find.text('읽지 않음 2'), findsNothing);
    expect(find.byKey(const ValueKey('unread-한강')), findsNothing);
    expect(find.byKey(const ValueKey('unread-정릉')), findsNothing);
  });

  testWidgets('read all puts the dots back when it fails', (tester) async {
    api
      ..inboxItems.add(item('한강'))
      ..failRead = true;
    await pumpHome(tester);
    await openInbox(tester);

    await tester.tap(find.text('모두 읽음'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unread-한강')), findsOneWidget);
    expect(find.text('연결 실패'), findsOneWidget);
  });

  testWidgets('scrolling to the end loads the next page', (tester) async {
    api.inboxItems.addAll([for (var i = 0; i < 30; i++) item('코스$i', ago: Duration(hours: i + 1), read: true)]);
    await pumpHome(tester);
    await openInbox(tester);
    expect(api.inboxCursors, [null]);

    await tester.scrollUntilVisible(find.text('‘코스29’ 코스가 7일 뒤 만료돼요.'), 300);
    await tester.pumpAndSettle();

    expect(api.inboxCursors, [null, '20']);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: '마지막 쪽이면 더 받지 않는다');
  });

  testWidgets('a page that does not fill the screen loads the next one by itself', (tester) async {
    api
      ..pageSize = 3
      ..inboxItems.addAll([for (var i = 0; i < 5; i++) item('코스$i', ago: Duration(hours: i + 1), read: true)]);
    await pumpHome(tester);
    await openInbox(tester);

    // 스크롤할 것이 없어도 다음 쪽을 받는다
    expect(api.inboxCursors, [null, '3']);
    expect(find.text('‘코스4’ 코스가 7일 뒤 만료돼요.'), findsOneWidget);
  });

  testWidgets('an empty inbox says so', (tester) async {
    await pumpHome(tester);
    expect(dot, findsNothing);

    await openInbox(tester);

    expect(find.text(NotificationInboxScreen.emptyTitle), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    api.failInbox = true;
    await pumpHome(tester);
    expect(dot, findsNothing, reason: '수를 못 받으면 점을 보이지 않는다');
    await openInbox(tester);
    expect(find.text(NotificationInboxScreen.loadFailedTitle), findsOneWidget);

    api
      ..failInbox = false
      ..inboxItems.add(item('한강'));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('‘한강’ 코스가 7일 뒤 만료돼요.'), findsOneWidget);
    expect(find.text('읽지 않음 1'), findsOneWidget);
  });

  test('received time reads like the wireframe', () {
    String at(Duration ago) => formatNotificationTime(now.subtract(ago), now);
    expect(at(const Duration(seconds: 30)), '방금');
    expect(at(const Duration(minutes: 12)), '12분 전');
    expect(at(const Duration(hours: 1)), '1시간 전');
    expect(at(const Duration(hours: 23)), '23시간 전');
    expect(at(const Duration(hours: 30)), '어제'); // 서울 11월 3일 오전 6시
    expect(at(const Duration(days: 2)), '2일 전');
    expect(at(const Duration(days: 29)), '29일 전');
  });
}
