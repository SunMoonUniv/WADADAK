import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/course_tracker.dart';
import 'package:wadadak/features/run/domain/free_run_session.dart';
import 'package:wadadak/features/run/domain/ghost_live_comparison.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/domain/run_lap.dart';
import 'package:wadadak/features/run/presentation/course_start_view.dart';
import 'package:wadadak/features/run/presentation/free_run_live_view.dart';
import 'package:wadadak/features/run/presentation/free_run_result_view.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

void main() {
  setUpAll(() async {
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

  final variants = <(String, Size, double)>[
    ('normal', const Size(402, 874), 1),
    ('compact', const Size(360, 640), 1),
    ('small-large-text', const Size(320, 568), 1.3),
    ('accessibility', const Size(402, 874), 2),
    ('landscape', const Size(740, 360), 1),
    ('small-accessibility', const Size(320, 568), 2),
    ('landscape-accessibility', const Size(740, 360), 2),
  ];

  RunSnapshot snapshot(RunState state) => RunSnapshot(
    state: state,
    sessionId: 'qa',
    startedAt: DateTime.utc(2026, 11, 3),
    elapsed: const Duration(hours: 1, minutes: 4, seconds: 12),
    active: const Duration(minutes: 59, seconds: 34),
    distanceMeters: 10520,
    inputs: const [],
    segments: const [
      [RunPoint(36, 127), RunPoint(36.01, 127)],
    ],
    averageCadence: 174,
    currentCadence: 180,
    estimatedCaloriesKcal: 683.8,
    notice: state == RunState.finished
        ? null
        : 'GPS 신호가 약해요. 신호가 돌아오면 계속 측정해요.',
    storageStatus: '기기 저장 · 동기화 확인 필요',
    laps: const [
      RunLap(
        number: 1,
        distanceM: 1000,
        movingMs: 300000,
        elapsedMs: 305000,
        complete: true,
      ),
      RunLap(
        number: 2,
        distanceM: 410,
        movingMs: 123000,
        elapsedMs: 125000,
        complete: false,
      ),
    ],
  );
  final course = CourseStart(
    'qa-course',
    const CourseSelection('c1', '한강 산책로에서 달리는 저녁 코스'),
    CourseSnapshot(
      sessionId: 'qa-course',
      courseId: 'c1',
      route: const [GeoPoint(36, 127), GeoPoint(36.01, 127)],
      totalDistanceMeters: 1111,
      version: 1,
    ),
    const GeoPoint(36, 127),
  );

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    const directory = String.fromEnvironment('QA_CAPTURE_DIR');
    if (directory.isEmpty) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bitmap = await boundary.toImage();
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      bitmap.dispose();
    });
  }

  for (final (name, size, scale) in variants) {
    for (final screen in [
      'preparation',
      'course-start',
      'free-live',
      'ghost-paused',
      'result',
    ]) {
      testWidgets('QA layout $screen $name', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        final controller = FreeRunController(
          createSession: () => FreeRunSession(
            monotonicNow: () => Duration.zero,
            utcNow: () => DateTime.utc(2026),
          ),
          createId: () => 'qa',
        );
        addTearDown(controller.dispose);
        final child = switch (screen) {
          'preparation' => const FreeRunScreen(),
          'course-start' => CourseStartView(
            start: course,
            onStart: () {},
            onCancel: () {},
            error: '인터넷에 연결되지 않아 코스 러닝을 시작할 수 없어요. 연결을 확인하고 다시 시도해 주세요.',
          ),
          'free-live' => FreeRunLiveView(
            run: snapshot(RunState.running),
            onPause: () {},
            onResume: () {},
            onStop: () {},
          ),
          'ghost-paused' => FreeRunLiveView(
            run: snapshot(RunState.paused),
            ghostOpponent: '내 기록 01:02:30',
            ghostComparison: const GhostLiveComparison(
              distanceM: -45,
              timeDeltaMs: 14000,
            ),
            course: CourseLive(
              '한강 산책로에서 달리는 저녁 코스',
              CourseTracker(RouteGeometry(course.snapshot.route)),
            ),
            onPause: () {},
            onResume: () {},
            onStop: () {},
          ),
          _ => FreeRunResultView(
            run: snapshot(RunState.finished),
            onConfirm: () {},
          ),
        };
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              mapEngineProvider.overrideWithValue(MapEngine.dev),
              freeRunControllerProvider.overrideWithValue(controller),
            ],
            child: MaterialApp(
              theme: WdTheme.light(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                  padding: const EdgeInsets.only(top: 24, bottom: 16),
                ),
                child: RepaintBoundary(key: key, child: child),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (screen == 'course-start') {
          debugPrint(
            'QA course controls $name cancel=${tester.getRect(find.widgetWithText(WdButton, '취소'))} '
            'start=${tester.getRect(find.byType(RunHoldToStart))} safeBottom=${size.height - 16}',
          );
        }
        await capture(tester, key, '$screen-$name');
        expect(
          tester.takeException(),
          isNull,
          reason:
              'User must be able to read and operate $screen at $size, text scale $scale.',
        );
        if (screen == 'course-start') {
          expect(
            find.widgetWithText(WdButton, '취소').hitTestable(),
            findsOneWidget,
          );
          expect(find.byType(RunHoldToStart).hitTestable(), findsOneWidget);
          expect(
            tester.getRect(find.widgetWithText(WdButton, '취소')).bottom,
            lessThanOrEqualTo(size.height - 16),
          );
          expect(
            tester.getSize(find.byType(MapView)).height,
            greaterThanOrEqualTo(160),
          );
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expect(
            find
                .text('인터넷에 연결되지 않아 코스 러닝을 시작할 수 없어요. 연결을 확인하고 다시 시도해 주세요.')
                .hitTestable(),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(WdButton, '취소').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await capture(tester, key, '$screen-$name-scrolled');
        }
        if (screen == 'free-live' || screen == 'ghost-paused') {
          await tester.drag(
            find.byType(PageView),
            Offset(-size.width * .85, 0),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'All metric pages must support large text.',
          );
          await capture(tester, key, '$screen-$name-details');
          await tester.drag(find.byType(PageView), Offset(size.width * .85, 0));
          await tester.pumpAndSettle();
          await tester.drag(find.byType(PageView), Offset(size.width * .85, 0));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Map and progress labels must remain readable.',
          );
          await capture(tester, key, '$screen-$name-map');
        }
      });
    }
    testWidgets('QA end dialog can cancel $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = FreeRunSession(
        monotonicNow: () => Duration.zero,
        utcNow: () => DateTime.utc(2026),
      );
      session.start('qa');
      session.pause();
      final controller = FreeRunController(
        createSession: () => session,
        createId: () => 'qa',
      );
      addTearDown(controller.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [freeRunControllerProvider.overrideWithValue(controller)],
          child: MaterialApp(
            theme: WdTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: key, child: child!),
            ),
            home: const FreeRunScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('러닝 종료'));
      await tester.pumpAndSettle();
      await capture(tester, key, 'end-dialog-$name');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(controller.snapshot.state, RunState.paused);
    });
  }
}
