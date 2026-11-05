import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/notification_api_client.dart';
import 'package:wadadak/core/auth/auth_controller.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/push/push_service.dart';
import 'package:wadadak/push_binding.dart';
import 'package:wadadak/router.dart';
import 'package:wadadak/routes.dart';

import '../fakes.dart';

/// Firebase 대신. 알림을 눌렀거나 앱을 보고 있을 때 온 알림을 시험에서 직접 흘린다.
class FakePushMessaging implements PushMessaging {
  String? currentToken = 'fcm-1';
  PushNotice? launch;
  int deleted = 0;
  int permissionAsked = 0;
  bool failToken = false;
  final refreshes = StreamController<String>.broadcast();
  final taps = StreamController<PushNotice>.broadcast();
  final shown = StreamController<PushNotice>.broadcast();

  @override
  Future<String?> token() async {
    if (failToken) throw Exception('구글 플레이 서비스 없음');
    return currentToken;
  }

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Future<void> deleteToken() async {
    deleted++;
    currentToken = null;
  }

  @override
  Future<void> requestPermissionOnce() async => permissionAsked++;

  @override
  Future<PushNotice?> openedAtLaunch() async => launch;

  @override
  Stream<PushNotice> get opened => taps.stream;

  @override
  Stream<PushNotice> get foreground => shown.stream;
}

const _expiring = PushNotice(
  title: '내 코스 만료 임박',
  body: '‘한강 5km’ 코스가 7일 뒤 만료돼요.',
  data: {'type': 'COURSE_EXPIRING_SOON', 'courseId': 'c-1'},
);

const _tokens = AuthTokens(accessToken: 'x.eyJzdWIiOiJhbGljZSJ9.x', refreshToken: 'refresh');

void main() {
  late FakePushMessaging messaging;
  late FakeNotificationApi api;

  setUp(() {
    messaging = FakePushMessaging();
    api = FakeNotificationApi();
  });

  group('PushNotice', () {
    test('a course expiry notice opens that course', () {
      expect(_expiring.courseId, 'c-1');
    });

    test('an unknown kind opens nothing', () {
      expect(const PushNotice(data: {'type': 'RANK_CHANGED', 'courseId': 'c-1'}).courseId, isNull);
      expect(const PushNotice().courseId, isNull);
    });
  });

  group('PushService', () {
    test('register asks permission once and sends the token as an Android device', () async {
      final push = PushService(messaging, () => api);

      await push.register();

      expect(messaging.permissionAsked, 1);
      expect(api.registered, [('fcm-1', PushPlatform.android)]);
    });

    test('a refreshed token is registered again', () async {
      final push = PushService(messaging, () => api);
      await push.register();

      messaging.refreshes.add('fcm-2');
      await pumpEventQueue();

      expect(api.registered.last, ('fcm-2', PushPlatform.android));
    });

    test('register does not throw when the token cannot be read', () async {
      messaging.failToken = true;

      await PushService(messaging, () => api).register();

      expect(api.registered, isEmpty);
    });

    test('unregister removes the token on the server and drops it on the device', () async {
      final push = PushService(messaging, () => api);
      await push.register();

      await push.unregister();
      messaging.refreshes.add('fcm-2'); // 로그아웃 뒤 바뀐 토큰은 등록하지 않는다
      await pumpEventQueue();

      expect(api.removed, ['fcm-1']);
      expect(messaging.deleted, 1);
      expect(api.registered, hasLength(1));
    });

    test('without Firebase nothing is sent', () async {
      final push = PushService(null, () => api);

      await push.register();
      await push.unregister();

      expect(push.enabled, isFalse);
      expect(api.registered, isEmpty);
      expect(api.removed, isEmpty);
    });
  });

  test('logout removes the push token before the login tokens are cleared', () async {
    final storage = MemoryTokenStorage(_tokens);
    final container = ProviderContainer(overrides: [
      tokenStorageProvider.overrideWithValue(storage),
      memberApiClientProvider.overrideWithValue(FakeMemberApi()),
      pushMessagingProvider.overrideWithValue(messaging),
      notificationApiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    await container.read(authControllerProvider.notifier).logout();

    expect(api.removed, ['fcm-1']);
    expect(messaging.deleted, 1);
    expect(container.read(authControllerProvider).value, isA<SignedOut>());
  });

  group('PushBinding', () {
    Future<void> pumpApp(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: Routes.home,
        routes: [
          GoRoute(path: Routes.login, builder: (_, _) => const Scaffold(body: Text('A1'))),
          GoRoute(path: Routes.home, builder: (_, _) => const Scaffold(body: Text('A2'))),
          GoRoute(
            path: '/course/:courseId',
            builder: (_, state) => Scaffold(body: Text('B1 ${state.pathParameters['courseId']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(MemoryTokenStorage(_tokens)),
          memberApiClientProvider.overrideWithValue(FakeMemberApi()),
          pushMessagingProvider.overrideWithValue(messaging),
          notificationApiClientProvider.overrideWithValue(api),
          routerProvider.overrideWithValue(router),
        ],
        child: Consumer(
          builder: (_, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(routerProvider),
            builder: (_, child) => PushBinding(child: child!),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('signing in registers the device token', (tester) async {
      await pumpApp(tester);

      expect(api.registered, [('fcm-1', PushPlatform.android)]);
    });

    testWidgets('tapping a notification opens B1 above the current screen', (tester) async {
      await pumpApp(tester);

      messaging.taps.add(_expiring);
      await tester.pumpAndSettle();

      expect(find.text('B1 c-1'), findsOneWidget);
    });

    testWidgets('a notification that launched the app opens B1', (tester) async {
      messaging.launch = _expiring;
      await pumpApp(tester);

      expect(find.text('B1 c-1'), findsOneWidget);
    });

    testWidgets('a notification while the app is open shows a snack bar that opens B1', (tester) async {
      await pumpApp(tester);

      messaging.shown.add(_expiring);
      await tester.pumpAndSettle();
      expect(find.text('내 코스 만료 임박\n‘한강 5km’ 코스가 7일 뒤 만료돼요.'), findsOneWidget);

      await tester.tap(find.text('보기'));
      await tester.pumpAndSettle();

      expect(find.text('B1 c-1'), findsOneWidget);
    });

    testWidgets('tapping a notification marks it read in the inbox', (tester) async {
      await pumpApp(tester);

      messaging.taps.add(const PushNotice(
        title: '내 코스 만료 임박',
        data: {'type': 'COURSE_EXPIRING_SOON', 'courseId': 'c-1', 'notificationId': 'n-1'},
      ));
      await tester.pumpAndSettle();

      expect(api.markedRead, ['n-1']);
      expect(find.text('B1 c-1'), findsOneWidget);
    });

    testWidgets('an unknown notification is marked read but opens nothing', (tester) async {
      messaging.launch = const PushNotice(data: {'type': 'SOMETHING_NEW', 'notificationId': 'n-2'});
      await pumpApp(tester);

      expect(api.markedRead, ['n-2'], reason: '모르는 종류라도 읽음으로 바꾼다');
      expect(find.text('A2'), findsOneWidget, reason: '모르는 종류는 화면을 열지 않는다');
    });
  });
}
