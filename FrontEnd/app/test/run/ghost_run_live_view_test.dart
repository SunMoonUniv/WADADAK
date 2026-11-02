import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/course_tracker.dart';
import 'package:wadadak/features/run/domain/ghost_live_comparison.dart';
import 'package:wadadak/features/run/domain/run_lap.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_live_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('live gap preserves signs and unknown values', () {
    const ahead = GhostLiveComparison(distanceM: 12, timeDeltaMs: -4000);
    expect(ahead.value, '+12 m');
    expect(ahead.caption, '약 4초 앞서는 중');
    expect(ahead.distance, '12m 앞서요');
    expect(ahead.time, '4초 앞서요');
    const behind = GhostLiveComparison(distanceM: -12, timeDeltaMs: 4000);
    expect(behind.value, '-12 m');
    expect(behind.caption, '약 4초 뒤처지는 중');
    expect(const GhostLiveComparison().value, '—');
    expect(const GhostLiveComparison(distanceM: 0).title, '고스트와 나란히 달리고 있어요');
  });

  RunSnapshot snapshot({bool paused = false}) => RunSnapshot(
    sessionId: 'ghost-ui',
    startedAt: DateTime.utc(2026, 11, 2),
    state: paused ? RunState.paused : RunState.running,
    elapsed: const Duration(minutes: 13, seconds: 2),
    active: const Duration(minutes: 12, seconds: 34),
    distanceMeters: 2410,
    inputs: const [],
    segments: const [
      [RunPoint(37.5, 127), RunPoint(37.51, 127)],
    ],
    paceDisplayManaged: true,
    averagePaceDisplay: 313,
    currentCadence: 178,
    liveElevationGainM: 42,
    laps: const [
      RunLap(
        number: 1,
        distanceM: 1000,
        movingMs: 318000,
        elapsedMs: 320000,
        complete: true,
      ),
      RunLap(
        number: 2,
        distanceM: 1000,
        movingMs: 308000,
        elapsedMs: 310000,
        complete: true,
      ),
      RunLap(
        number: 3,
        distanceM: 410,
        movingMs: 128740,
        elapsedMs: 130000,
        complete: false,
      ),
    ],
  );

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    const out = String.fromEnvironment('GHOST_LIVE_CAPTURE_DIR');
    if (out.isEmpty) return;
    void repaint(RenderObject object) {
      object.markNeedsPaint();
      object.visitChildren(repaint);
    }

    repaint(key.currentContext!.findRenderObject()!);
    await tester.pump();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bitmap = await boundary.toImage();
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$out/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      bitmap.dispose();
    });
  }

  for (final width in [402.0, 320.0]) {
    testWidgets('ghost basic, map, detail and pause fit $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, width == 402 ? 874 : 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controls = <String>[];
      final key = GlobalKey();
      final course = CourseLive(
        '한강 야경 5K',
        CourseTracker(
          RouteGeometry(const [GeoPoint(37.5, 127), GeoPoint(37.54676, 127)]),
        ),
      );
      Future<void> show({
        bool paused = false,
        GhostLiveComparison comparison = const GhostLiveComparison(
          distanceM: 12,
          timeDeltaMs: -4000,
          ghostProgress: 0.46,
          position: GeoPoint(37.51, 127),
        ),
      }) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
            child: MaterialApp(
              theme: WdTheme.light(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 874),
                  padding: const EdgeInsets.only(top: 40, bottom: 14),
                ),
                child: RepaintBoundary(
                  key: key,
                  child: FreeRunLiveView(
                    run: snapshot(paused: paused),
                    course: course,
                    ghostOpponent: '내 최고 기록',
                    ghostComparison: comparison,
                    onPause: () => controls.add('pause'),
                    onResume: () => controls.add('resume'),
                    onStop: () => controls.add('stop'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await show();
      expect(find.text('고스트보다 앞서고 있어요'), findsOneWidget);
      expect(find.text('+12 m'), findsOneWidget);
      expect(find.text('소모 칼로리'), findsNothing);
      expect(find.text('현재 0.41 km'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(WdGhostLeadCard)).dy,
        greaterThan(tester.getTopLeft(find.byType(WdElapsedTime)).dy),
      );
      await capture(tester, key, 'basic-${width.toInt()}');
      await tester.tap(find.text('일시정지'));
      expect(controls, ['pause']);
      await tester.tap(find.byKey(const ValueKey('run-metric-3')));
      await tester.pump();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('run-metric-3')))
            .properties
            .label,
        startsWith('시간,'),
      );

      await tester.drag(find.byType(PageView), Offset(width * 0.8, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final map = tester.widget<MapView>(find.byType(MapView));
      final ghost = map.markers.singleWhere((m) => m.id == 'ghost-opponent');
      expect(ghost.anchor, const Offset(0.5, 1));
      expect(ghost.icon, WdIcons.ghostMapPin);
      await capture(tester, key, 'map-${width.toInt()}');
      await tester.drag(find.byType(PageView), Offset(-width * 0.8, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), Offset(-width * 0.8, 0));
      await tester.pumpAndSettle();
      expect(find.byType(WdRunMetricTile), findsNWidgets(6));
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'details-${width.toInt()}');
      await tester.drag(find.byType(PageView), Offset(width * 0.8, 0));
      await tester.pumpAndSettle();
      await show(
        paused: true,
        comparison: const GhostLiveComparison(
          distanceM: -12,
          timeDeltaMs: 4000,
        ),
      );
      expect(find.text('고스트를 따라잡고 있어요'), findsOneWidget);
      await capture(tester, key, 'paused-${width.toInt()}');
      await tester.tap(find.text('계속 달리기'));
      await tester.tap(find.text('러닝 종료'));
      expect(controls, ['pause', 'resume', 'stop']);
      expect(tester.takeException(), isNull);
      await show(comparison: const GhostLiveComparison());
      expect(find.text('고스트 위치를 확인하고 있어요'), findsOneWidget);
      expect(find.text('약 4초 앞서는 중'), findsNothing);
    });
  }
}
