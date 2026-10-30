import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/domain/free_run_session.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak/router.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/api/member_api_client.dart';

import '../fakes.dart';

void main() {
  late Duration tick;
  late int ids;
  late FreeRunController controller;
  setUp(() {
    tick = Duration.zero;
    ids = 0;
    controller = FreeRunController(
      createSession: () => FreeRunSession(
        monotonicNow: () => tick,
        utcNow: () => DateTime.utc(2026),
      ),
      createId: () => 'session-${++ids}',
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [freeRunControllerProvider.overrideWithValue(controller)],
        child: MaterialApp(theme: WdTheme.light(), home: const FreeRunScreen()),
      ),
    );
  }

  Future<void> holdStart(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('자유 러닝 시작')),
    );
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump();
  }

  testWidgets(
    'course run tab shows C6 to pick a course instead of jumping to course select (RUN-03)',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('코스 러닝'));
      await tester.pumpAndSettle();

      expect(find.text('코스를 골라 주세요'), findsOneWidget);
      expect(find.text('코스를 고르면 시작할 수 있어요'), findsOneWidget);
      expect(
        tester
            .widget<WdButton>(find.widgetWithText(WdButton, '코스 러닝 시작'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('자유 러닝'));
      await tester.pumpAndSettle();
      expect(find.text('자유 러닝 시작'), findsOneWidget);
      expect(find.text('코스를 골라 주세요'), findsNothing);
    },
  );

  testWidgets('short press and cancelled countdown create no session', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('내 러닝 기록 보기'), findsNothing);
    await tester.tap(find.text('자유 러닝 시작'));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.countdown, isNull);
    expect(ids, 0);
    await holdStart(tester);
    expect(controller.countdown, 3);
    await tester.tap(find.text('시작 취소'));
    await tester.pump(const Duration(seconds: 4));
    expect(controller.snapshot.state, RunState.ready);
    expect(controller.snapshot.inputs, isEmpty);
    expect(ids, 0);
  });

  testWidgets('start pause resume confirm end and new run work on screen', (
    tester,
  ) async {
    await mount(tester);
    await holdStart(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(controller.snapshot.state, RunState.running);
    expect(ids, 1);
    tick = const Duration(seconds: 40);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('일시정지').last);
    await tester.pump();
    tick = const Duration(seconds: 60);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:40'), findsOneWidget);
    expect(find.text('총 소요 시간 01:00 (정지 시간 포함)'), findsOneWidget);
    await tester.tap(find.text('계속 달리기'));
    await tester.pump();
    tick = const Duration(seconds: 120);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('일시정지').last);
    await tester.pump();
    await tester.tap(find.text('러닝 종료'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(controller.snapshot.state, RunState.paused);
    await tester.tap(find.text('러닝 종료'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('종료'));
    await tester.pumpAndSettle();
    expect(find.text('러닝 결과'), findsOneWidget);
    expect(find.text('02:00'), findsOneWidget);
    expect(find.textContaining('달린 시간 01:40'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pump();
    expect(controller.snapshot.state, RunState.ready);
    expect(controller.snapshot.inputs, isEmpty);
  });

  testWidgets('the real running tab keeps the session when visiting home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapEngineProvider.overrideWithValue(MapEngine.dev),
          courseApiClientProvider.overrideWithValue(FakeCourseApi()),
          freeRunControllerProvider.overrideWithValue(controller),
          tokenStorageProvider.overrideWithValue(
            MemoryTokenStorage(testTokens),
          ),
          memberApiClientProvider.overrideWithValue(FakeMemberApi()),
        ],
        child: const WadadakApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('달리기'));
    await tester.pumpAndSettle();
    await holdStart(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(WdBottomNav), findsNothing);
    // 전체 화면에서도 다른 경로로 이동했다 돌아오면 같은 세션을 유지한다.
    ProviderScope.containerOf(tester.element(find.byType(FreeRunScreen)))
        .read(routerProvider)
        .go(Routes.home);
    await tester.pumpAndSettle();
    tick = const Duration(seconds: 10);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('달리기'));
    await tester.pumpAndSettle();
    expect(controller.snapshot.state, RunState.running);
    expect(find.text('00:10'), findsOneWidget);
    controller.discard();
    await tester.pump();
  });
}
