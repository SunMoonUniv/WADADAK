import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_live_view.dart';
import 'package:wadadak/features/run/presentation/run_lap_list.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

Finder slot(int number) => find.byKey(ValueKey('run-metric-$number'));
String selected(WidgetTester tester, int number) =>
    tester.widget<Semantics>(slot(number)).properties.label!;

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

  RunSnapshot snapshot({
    String id = 'one',
    RunState phase = RunState.running,
    double? cadence = 178,
    double? pace = 300,
  }) => RunSnapshot(
    state: phase,
    sessionId: id,
    startedAt: DateTime.utc(2026, 10, 15),
    elapsed: const Duration(seconds: 240),
    active: const Duration(seconds: 220),
    moving: const Duration(seconds: 200),
    distanceMeters: 400,
    inputs: const [],
    segments: [
      [RunPoint(36, 127), RunPoint(36.001, 127)],
    ],
    paceDisplayManaged: true,
    averagePaceDisplay: 500,
    currentPaceDisplay: pace,
    currentCadence: cadence,
  );

  Future<void> show(
    WidgetTester tester,
    RunSnapshot run, {
    GlobalKey? capture,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
      child: MaterialApp(
        theme: WdTheme.light(),
        home: RepaintBoundary(
          key: capture,
          child: FreeRunLiveView(
            run: run,
            onPause: () {},
            onResume: () {},
            onStop: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'each basic metric cycles independently with label, value and unit',
    (tester) async {
      await show(tester, snapshot());
      expect(selected(tester, 0), '시간, 03:40');
      expect(find.text('이동 시간'), findsOneWidget);
      expect(selected(tester, 1), contains('거리, 0.40 km'));
      expect(selected(tester, 2), contains('평균 페이스, 8′20″ /km'));
      expect(selected(tester, 3), contains('현재 페이스, 5′00″ /km'));
      final unchanged = [for (var i = 0; i < 4; i++) selected(tester, i)];
      await tester.tap(slot(1));
      await tester.pump();
      expect(
        selected(tester, 1),
        unchanged[2],
      ); // Duplicate selection is independent.
      for (final i in [0, 2, 3]) {
        expect(selected(tester, i), unchanged[i]);
      }
      for (var i = 0; i < 5; i++) {
        await tester.tap(slot(1));
        await tester.pump();
        if (i == 2) expect(selected(tester, 1), '심박수, —');
      }
      expect(selected(tester, 1), unchanged[1]);
      for (final i in [0, 2, 3]) {
        final before = selected(tester, i);
        for (var tap = 0; tap < 6; tap++) {
          await tester.tap(slot(i));
          await tester.pump();
        }
        expect(selected(tester, i), before);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'total time stays fixed outside metric taps and hidden time choices stay absent',
    (tester) async {
      await show(tester, snapshot(phase: RunState.paused));
      final caption = find.text('총 소요 시간 04:00 (정지 시간 포함)');
      expect(caption, findsOneWidget);
      await tester.tap(caption);
      await tester.pump();
      expect(selected(tester, 0), '시간, 03:40');
      final labels = <String>{};
      for (var i = 0; i < 6; i++) {
        labels.add(selected(tester, 0).split(',').first);
        expect(caption, findsOneWidget);
        await tester.tap(slot(0));
        await tester.pump();
      }
      expect(labels, {'시간', '거리', '평균 페이스', '현재 페이스', '케이던스', '심박수'});
      expect(selected(tester, 0), '시간, 03:40');
      for (final direction in [-700.0, 700.0, 700.0]) {
        await tester.drag(find.byType(PageView), Offset(direction, 0));
        await tester.pumpAndSettle();
        for (final element in find.textContaining('이동 시간').evaluate()) {
          expect(
            element.findAncestorWidgetOfExactType<RunLapList>(),
            isNotNull,
          );
        }
        expect(find.textContaining('이동시간'), findsNothing);
        expect(find.textContaining('달린'), findsNothing);
        expect(find.textContaining('일시정지 '), findsNothing);
        expect(find.text('정지시간'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection survives updates, pauses and slides but resets for a new session',
    (tester) async {
      await show(tester, snapshot());
      await tester.tap(slot(3));
      await tester.pump();
      expect(selected(tester, 3), contains('케이던스, 178 spm'));
      await show(tester, snapshot(phase: RunState.paused, cadence: null));
      expect(selected(tester, 3), contains('케이던스, —'));
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(700, 0));
      await tester.pumpAndSettle();
      expect(selected(tester, 3), contains('케이던스, —'));
      await show(tester, snapshot(cadence: 0));
      expect(selected(tester, 3), contains('케이던스, 0 spm'));
      await show(tester, snapshot(id: 'new'));
      expect(selected(tester, 3), startsWith('현재 페이스,'));
    },
  );

  testWidgets(
    'dragging on a metric still switches pages without changing its selection',
    (tester) async {
      await show(tester, snapshot());
      final before = selected(tester, 0);
      await tester.drag(slot(0), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(find.text('연결하지 않은 센서는 —로 표시해요.'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(700, 0));
      await tester.pumpAndSettle();
      expect(selected(tester, 0), before);
    },
  );

  for (final width in [320.0, 402.0]) {
    testWidgets(
      'all metric types fit ${width.toInt()}px and retain pause control',
      (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final capture = GlobalKey();
        await show(tester, snapshot(), capture: capture);
        for (var i = 0; i < 6; i++) {
          await tester.tap(slot(0));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('일시정지'), findsOneWidget);
          const out = String.fromEnvironment('RUN_TOUCH_CAPTURE_DIR');
          if (out.isNotEmpty) {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$out/${width.toInt()}-metric-$i.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      },
    );
  }

  testWidgets(
    'metric taps leave measurement values and recording controls untouched',
    (tester) async {
      final run = snapshot();
      final controls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: WdTheme.light(),
          home: FreeRunLiveView(
            run: run,
            onPause: () => controls.add('pause'),
            onResume: () => controls.add('resume'),
            onStop: () => controls.add('stop'),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.tap(slot(i));
        await tester.pump();
      }
      expect(controls, isEmpty);
      expect(run.state, RunState.running);
      expect(run.elapsed, const Duration(seconds: 240));
      expect(run.active, const Duration(seconds: 220));
      expect(run.movingTime, const Duration(seconds: 200));
      expect(run.distanceMeters, 400);
      expect(run.inputs, isEmpty);
      await tester.tap(find.text('일시정지'));
      expect(controls, ['pause']);
    },
  );
}
