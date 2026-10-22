import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/course_format.dart';
import 'package:wadadak/features/course/create/gps_course_intro.dart';
import 'package:wadadak/features/course/create/route_draw_screen.dart';
import 'package:wadadak/features/home/home_screen.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/domain/free_run_session.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak/router.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

/// 코스 상세에서 고른 코스를 비웠는지 센다. 측정은 기기 없이 도는 자유 러닝 세션이다.
class _SpyFreeRun extends FreeRunController {
  _SpyFreeRun()
      : super(
          createSession: () => FreeRunSession(monotonicNow: () => Duration.zero, utcNow: () => DateTime.utc(2026)),
          createId: () => 'session-1',
        );

  var cleared = 0;

  @override
  void clearCourse() => cleared++;
}

/// B5 코스 만들기 — 내가 달려서 등록.
void main() {
  late FakeCourseApi courses;
  late _SpyFreeRun run;

  setUp(() {
    courses = FakeCourseApi();
    run = _SpyFreeRun();
  });
  tearDown(() => run.dispose());

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 홈 → B3 → `내가 달려서 등록` 탭. 찍은 점이 없어 확인 없이 바뀐다(B3-07).
  Future<void> openRunMethod(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        memberApiClientProvider.overrideWithValue(FakeMemberApi()),
        tokenStorageProvider.overrideWithValue(MemoryTokenStorage(testTokens)),
        socialLoginProvider.overrideWithValue(FakeSocialLogin()),
        runPermissionsProvider.overrideWithValue(FakeRunPermissions()),
        mapEngineProvider.overrideWithValue(MapEngine.dev),
        courseApiClientProvider.overrideWithValue(courses),
        myLocationProvider.overrideWithValue(FakeMyLocation()),
        freeRunControllerProvider.overrideWithValue(run),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
    await tap(tester, find.text('＋ 코스 만들기'));
    await tap(tester, find.text('내가 달려서 등록'));
  }

  VoidCallback? button(WidgetTester tester, String label) =>
      tester.widget<WdButton>(find.widgetWithText(WdButton, label)).onPressed;

  testWidgets('explains how a run becomes a course (B5-01 · B5-02)', (tester) async {
    await openRunMethod(tester);

    expect(find.text('직접 달린 경로가 그대로 코스가 돼요'), findsOneWidget);
    for (final step in ['달리기 시작', '자동 변환', '정보 입력 후 등록']) {
      expect(find.text(step), findsOneWidget);
    }
    expect(find.text(GpsCourseIntro.conditions), findsOneWidget);
    expect(find.text(gpsQuotaUsedUpMessage), findsNothing);
    expect(find.text('한강'), findsOneWidget, reason: '예시 경로 그림의 지명');
    expect(button(tester, '내 기록에서 코스 올리기'), isNotNull);
    expect(button(tester, '달리기 시작하기'), isNotNull);
  });

  testWidgets('starts a free run and forgets a course picked on a course page (B5-03)', (tester) async {
    await openRunMethod(tester);

    await tap(tester, find.text('달리기 시작하기'));

    expect(run.cleared, 1);
    expect(find.byType(FreeRunScreen), findsOneWidget);
    expect(find.text('자유 러닝 시작'), findsOneWidget, reason: 'C5 자유 러닝 준비');
    expect(find.byType(RouteDrawScreen), findsNothing, reason: '코스 만들기는 닫힌다');
  });

  testWidgets('leaves a run in progress as it is (RUN-05)', (tester) async {
    await openRunMethod(tester);
    await tap(tester, find.text('달리기 시작하기'));
    final gesture = await tester.startGesture(tester.getCenter(find.text('자유 러닝 시작')));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump(const Duration(seconds: 3));
    expect(run.snapshot.state, RunState.running);

    // 달리는 중에 홈에서 다시 코스 만들기로 와서 `달리기 시작하기`를 누른다.
    ProviderScope.containerOf(tester.element(find.byType(FreeRunScreen))).read(routerProvider).go(Routes.home);
    await tester.pumpAndSettle();
    await tap(tester, find.text('＋ 코스 만들기'));
    await tap(tester, find.text('내가 달려서 등록'));
    await tap(tester, find.text('달리기 시작하기'));

    expect(run.cleared, 1, reason: '처음 한 번만 비운다');
    expect(run.snapshot.state, RunState.running);
    run.discard();
    await tester.pump();
  });

  testWidgets('blocks both buttons when today\'s GPS courses are all registered', (tester) async {
    courses.quota = const RegistrationQuota(
      custom: TypeQuota(limit: 1, remaining: 1),
      gps: TypeQuota(limit: 3, remaining: 0),
    );
    await openRunMethod(tester);

    expect(find.text(gpsQuotaUsedUpMessage), findsOneWidget);
    expect(find.text(GpsCourseIntro.conditions), findsOneWidget);
    expect(button(tester, '내 기록에서 코스 올리기'), isNull);
    expect(button(tester, '달리기 시작하기'), isNull);
  });

  testWidgets('tells picking from past records is not ready yet (B5-04)', (tester) async {
    await openRunMethod(tester);

    await tap(tester, find.text('내 기록에서 코스 올리기'));

    expect(find.text(RouteDrawScreen.recordsNotReadyMessage), findsOneWidget);
    expect(find.byType(RouteDrawScreen), findsOneWidget);
  });

  testWidgets('goes home from the app bar without asking (B5-06)', (tester) async {
    await openRunMethod(tester);

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));

    expect(find.text('코스 만들기를 그만둘까요?'), findsNothing);
    expect(find.byType(RouteDrawScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
