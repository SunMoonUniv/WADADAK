import 'package:flutter/material.dart' show TabBarView;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/home/course_list_sheet.dart';
import 'package:wadadak/features/home/home_screen.dart';
import 'package:wadadak/features/my/my_screen.dart';
import 'package:wadadak/features/ranking/ranking_screen.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/domain/free_run_session.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak/router.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'fakes.dart';

void main() {
  late FreeRunController controller;
  late List<String> calls;
  setUp(() {
    controller = FreeRunController(
      createSession: () => FreeRunSession(
        monotonicNow: () => Duration.zero,
        utcNow: () => DateTime.utc(2026),
      ),
      createId: () => 'session',
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    calls = [];
    for (final channel in [
      SystemChannels.platform,
      const MethodChannel('com.wadadak.app/run_screen'),
    ]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method
            case 'moveToBack' || 'finish' || 'SystemNavigator.pop') {
          calls.add(call.method);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
    }
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
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'back goes home from other tabs, lowers the home list, then needs two presses to close',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('랭킹'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsNothing);

      await back(tester); // 다른 탭 → 홈
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(calls, isEmpty);

      // 홈 목록이 반쯤 올라와 있다 → 한 번 내리면 피크
      final sheet = find.byType(CourseListSheet);
      final half = tester.getTopLeft(sheet).dy;
      await back(tester);
      expect(
        tester.getTopLeft(find.byType(CourseListSheet)).dy,
        greaterThan(half),
      );
      expect(find.text('한 번 더 누르면 종료돼요'), findsNothing);
      expect(calls, isEmpty);

      // 피크에서는 한 번 누르면 안내만, 곧바로 한 번 더 누르면 닫는다
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('한 번 더 누르면 종료돼요'), findsOneWidget);
      expect(calls, isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, ['finish']); // Android가 직접 닫는다
    },
  );

  testWidgets('second press after the window only shows the notice again', (
    tester,
  ) async {
    await mount(tester);
    await back(tester); // 반 → 피크
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 3));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(calls, isEmpty);
    expect(find.text('한 번 더 누르면 종료돼요'), findsOneWidget);
  });

  testWidgets(
    'while measuring, back asks to end and closing from home only sends the app away',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('달리기'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('자유 러닝 시작')),
      );
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump(const Duration(seconds: 4));
      expect(controller.snapshot.state, RunState.running);
      expect(find.byType(WdBottomNav), findsNothing);

      // 측정 화면의 뒤로가기는 홈 탭으로 가지 않고 종료 확인 창을 띄운다
      await back(tester);
      expect(find.text('러닝을 종료할까요?'), findsOneWidget);
      expect(find.byType(FreeRunScreen), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(controller.snapshot.state, RunState.running);

      // 다른 길로 홈에 와 있으면(측정은 계속) 두 번 눌러도 앱을 닫지 않는다
      ProviderScope.containerOf(tester.element(find.byType(FreeRunScreen)))
          .read(routerProvider)
          .go(Routes.home);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      await back(tester); // 목록 내리기
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, ['moveToBack']); // 앱을 닫지 않는다
      expect(controller.snapshot.state, RunState.running);
      controller.discard();
      await tester.pump();
    },
  );

  testWidgets('tabs slide in the tapped direction and keep their screens', (
    tester,
  ) async {
    await mount(tester);
    final home = tester.getTopLeft(find.byType(HomeScreen)).dx;
    await tester.tap(find.text('랭킹'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 미끄러지는 중: 홈은 왼쪽으로 나가고 랭킹은 오른쪽에서 들어온다
    expect(tester.getTopLeft(find.byType(HomeScreen)).dx, lessThan(home));
    expect(tester.getTopLeft(find.byType(RankingScreen)).dx, greaterThan(home));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsNothing); // 화면에서 빠지고 상태는 남는다
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(tester.getTopLeft(find.byType(RankingScreen)).dx, home);
  });

  testWidgets('swiping moves to the next tab, a short swipe springs back', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('MY'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(MyScreen), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(find.byType(MyScreen), findsOneWidget); // 조금 밀면 제자리

    await tester.drag(find.byType(MyScreen), const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(find.byType(MyScreen), findsOneWidget); // 끝 탭에서는 더 가지 않는다

    await tester.drag(find.byType(MyScreen), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(find.byType(RankingScreen), findsOneWidget); // 오른쪽으로 밀면 왼쪽 탭
    expect(find.byType(MyScreen), findsNothing);
  });

  testWidgets(
    'ranking swipes its own tabs first and hands the edge swipe to the app tabs',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('랭킹'));
      await tester.pumpAndSettle();
      final page = find.byType(TabBarView);

      await tester.drag(page, const Offset(-250, 0)); // 거리 → 지역(랭킹 안)
      await tester.pumpAndSettle();
      expect(find.byType(RankingScreen), findsOneWidget);
      expect(find.byType(MyScreen), findsNothing);

      await tester.drag(page, const Offset(-250, 0)); // 지역이 끝 → MY
      await tester.pumpAndSettle();
      expect(find.byType(MyScreen), findsOneWidget);
      expect(find.byType(RankingScreen), findsNothing);
    },
  );
}
