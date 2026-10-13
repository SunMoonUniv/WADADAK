import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/domain/free_run_session.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak/main_shell.dart';
import 'package:wadadak/router.dart';
import 'package:wadadak/routes.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // 실제 앱과 같은 글꼴로 화면 폭·줄바꿈을 검증한다.
    final fonts = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      fonts.addFont(
        rootBundle.load(
          'packages/wadadak_design_system/assets/fonts/Pretendard-$weight.otf',
        ),
      );
    }
    await fonts.load();
  });

  for (final size in [const Size(402, 874), const Size(320, 640)]) {
    testWidgets(
      'Figma running screens keep controls usable at ${size.width.toInt()}px',
      (tester) async {
        var tick = Duration.zero;
        final controller = FreeRunController(
          createSession: () => FreeRunSession(
            monotonicNow: () => tick,
            utcNow: () => DateTime.utc(2026, 10, 13),
          ),
          createId: () => 'design-session',
        );
        final captureKey = GlobalKey();
        final router = GoRouter(
          initialLocation: Routes.run,
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (_, _, shell) => MainShell(shell: shell),
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: Routes.home,
                      builder: (_, _) => const Scaffold(),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: Routes.run,
                      builder: (_, _) => const FreeRunScreen(),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: Routes.ranking,
                      builder: (_, _) => const Scaffold(),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: Routes.my,
                      builder: (_, _) => const Scaffold(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 40, bottom: 16);
        addTearDown(() {
          tester.view.reset();
          controller.dispose();
          router.dispose();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              freeRunControllerProvider.overrideWithValue(controller),
              routerProvider.overrideWithValue(router),
            ],
            child: RepaintBoundary(key: captureKey, child: const WadadakApp()),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> capture(String name) async {
          expect(tester.takeException(), isNull);
          const directory = String.fromEnvironment('RUN_DESIGN_CAPTURE_DIR');
          if (directory.isEmpty) return;
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          // 연속 캡처 시 이전 페이지의 retained layer도 새로 그린다.
          void repaint(RenderObject object) {
            object.visitChildren(repaint);
            object.markNeedsPaint();
          }

          repaint(boundary);
          await tester.pump();
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final target = File('$directory/${size.width.toInt()}-$name.png');
            await target.parent.create(recursive: true);
            await target.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        expect(find.byType(WdBottomNav), findsOneWidget);
        expect(find.text('오늘은, 발길이 닿는 대로.'), findsOneWidget);
        await capture('preparation');
        await tester.ensureVisible(find.text('자유 러닝 시작'));
        final hold = await tester.startGesture(
          tester.getCenter(find.text('자유 러닝 시작')),
        );
        await tester.pump(const Duration(seconds: 1));
        await hold.up();
        await tester.pump();
        expect(controller.countdown, 3);
        expect(find.byType(WdBottomNav), findsNothing);
        await capture('countdown');
        await tester.pump(const Duration(seconds: 3));
        tick = const Duration(seconds: 40);
        await tester.pump(const Duration(seconds: 1));
        await capture('live');

        await tester.drag(find.byType(PageView), Offset(-size.width, 0));
        await tester.pumpAndSettle();
        expect(find.text('연결하지 않은 센서는 —로 표시해요.'), findsOneWidget);
        await capture('metrics');
        await tester.drag(find.byType(PageView), Offset(size.width, 0));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PageView), Offset(size.width, 0));
        await tester.pumpAndSettle();
        expect(find.text('아직 위치 기록이 없어요'), findsOneWidget);
        await capture('map');
        await tester.drag(find.byType(PageView), Offset(-size.width, 0));
        await tester.pumpAndSettle();

        await tester.tap(find.text('일시정지').last);
        tick = const Duration(seconds: 60);
        await tester.pump(const Duration(seconds: 1));
        expect(controller.snapshot.active.inSeconds, 40);
        expect(controller.snapshot.elapsed.inSeconds, 60);
        await capture('paused');
        await tester.tap(find.text('러닝 종료'));
        await tester.pumpAndSettle();
        await capture('confirm');
        await tester.tap(find.text('종료'));
        await tester.pumpAndSettle();
        expect(find.text('러닝 완료 · 저장 전'), findsOneWidget);
        expect(find.byType(WdBottomNav), findsNothing);
        await capture('result');
        await tester.ensureVisible(find.text('구간 페이스'));
        await tester.pumpAndSettle();
        await capture('result-details');
        await tester.tap(find.text('확인'));
        await tester.pumpAndSettle();
        expect(controller.snapshot.state, RunState.ready);
        expect(find.byType(WdBottomNav), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
