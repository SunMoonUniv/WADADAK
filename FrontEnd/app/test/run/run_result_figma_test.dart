import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/run_lap.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/domain/run_result_stats.dart';
import 'package:wadadak/features/run/presentation/free_run_result_view.dart';
import 'package:wadadak/features/run/presentation/run_segment_analysis_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

RunSnapshot fixture({
  bool course = false,
  bool completed = true,
  int lapCount = 4,
}) => RunSnapshot(
  state: RunState.finished,
  sessionId: 'figma-result',
  startedAt: DateTime(2026, 9, 3, 19, 20),
  elapsed: const Duration(minutes: 22, seconds: 40),
  active: const Duration(minutes: 22, seconds: 5),
  distanceMeters: lapCount * 1000 + 100,
  inputs: const [],
  storageStatus: '기록 저장됨',
  gpsGapPassed: true,
  endReason: 'USER',
  moving: const Duration(minutes: 22, seconds: 5),
  averageCadence: 174,
  cadenceCoverageMs: 1325000,
  segments: const [
    [
      RunPoint(37.0, 127.0),
      RunPoint(37.001, 127.002),
      RunPoint(37.002, 127.003),
    ],
  ],
  laps: [
    for (var i = 0; i < lapCount; i++)
      RunLap(
        number: i + 1,
        distanceM: 1000,
        movingMs: [338, 330, 324, 334][i % 4] * 1000,
        elapsedMs: 340000,
        complete: true,
      ),
  ],
  resultStats: const RunResultStats(
    elevationGainM: 52,
    bestLapNumber: 3,
    bestLapPaceSecondsPerKm: 324,
    bestPaceSecondsPerKm: 312,
  ),
  course: course
      ? RunCourseResult.fromJson({
          'courseId': 'c1',
          'courseName': '한강 야경 5K',
          'courseDistanceMeters': 5210,
          'completed': completed,
          'reason': completed ? 'COMPLETED' : 'FINISH_NOT_REACHED',
          'recognizedDistanceMeters': completed ? 5210 : 3800,
          'progressPercent': completed ? 100 : 72.9,
          'reviewEligible': true,
          'courseElapsedSeconds': 1634,
        })
      : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      loader.addFont(
        rootBundle.load(
          'packages/wadadak_design_system/assets/fonts/Pretendard-$weight.otf',
        ),
      );
    }
    await loader.load();
    final material = FontLoader('MaterialIcons');
    material.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
  });
  Future<void> mount(
    WidgetTester tester,
    RunSnapshot run, {
    bool history = false,
    VoidCallback? onDelete,
    GlobalKey? capture,
    double width = 402,
    double height = 1349,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 40);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: WdTheme.light(),
            home: FreeRunResultView(
              run: run,
              onConfirm: () {},
              history: history,
              onDelete: onDelete,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    const dir = String.fromEnvironment('RUN_FIGMA_CAPTURE_DIR');
    if (dir.isEmpty) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final course in [false, true]) {
    for (final width in [320.0, 402.0]) {
      testWidgets(
        'D1 ${course ? 'course' : 'free'} summary and analysis at $width',
        (tester) async {
          final key = GlobalKey();
          await mount(
            tester,
            fixture(course: course),
            capture: key,
            width: width,
          );
          expect(find.text('구간 상세 분석'), findsOneWidget);
          expect(find.text('구간 페이스'), findsOneWidget);
          expect(find.text('랩 기록'), findsNothing);
          expect(find.text('3구간'), findsOneWidget);
          expect(find.textContaining('연속 30초 평균'), findsNothing);
          expect(
            find.text('코스로 등록할 수 있어요'),
            course ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'result-${course ? 'course' : 'free'}-${width.toInt()}',
          );
          await tester.tap(find.text('구간 상세 분석'));
          await tester.pumpAndSettle();
          expect(find.byType(RunSegmentAnalysisScreen), findsOneWidget);
          tester.view.physicalSize = Size(width, 902);
          await tester.pumpAndSettle();
          await capture(
            tester,
            key,
            'analysis-${course ? 'course' : 'free'}-${width.toInt()}',
          );
          expect(find.text('구간별 페이스 (1km 단위)'), findsOneWidget);
          await tester.tap(find.text('케이던스').first);
          await tester.pumpAndSettle();
          expect(find.text('구간별 케이던스 데이터가 없어요.'), findsOneWidget);
          await tester.tap(find.text('고도').first);
          await tester.pumpAndSettle();
          expect(find.text('구간별 고도 데이터가 없어요.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('history delete is left of share and footer opens analysis', (
    tester,
  ) async {
    var deletes = 0;
    final key = GlobalKey();
    await mount(
      tester,
      fixture(),
      history: true,
      capture: key,
      onDelete: () => deletes++,
    );
    final delete = find.byTooltip('기록 삭제');
    final share = find.bySemanticsLabel('러닝 결과 공유');
    expect(delete, findsOneWidget);
    expect(tester.getCenter(delete).dx, lessThan(tester.getCenter(share).dx));
    expect(tester.getSize(delete).width, greaterThanOrEqualTo(44));
    expect(find.widgetWithText(WdButton, '기록 삭제'), findsNothing);
    await capture(tester, key, 'result-history-402');
    await tester.tap(delete);
    expect(deletes, 1);
    await tester.tap(find.text('구간 상세 분석'));
    await tester.pumpAndSettle();
    expect(find.text('구간 분석'), findsOneWidget);
  });
  testWidgets(
    'unfinished course uses its message and long charts stay scrollable',
    (tester) async {
      await mount(
        tester,
        fixture(course: true, completed: false, lapCount: 30),
        width: 320,
      );
      expect(find.text('끝까지 달린 것만으로 충분해요.'), findsOneWidget);
      await tester.tap(find.text('구간 상세 분석'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
