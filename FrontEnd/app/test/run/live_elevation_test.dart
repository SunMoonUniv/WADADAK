import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/recording_models.dart' as r;
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/free_run_live_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'recording/run_controller_test.dart' as fake;

List<r.RunInput> inputs(dynamic json) => (json as List)
    .map((p) => r.RunInput.fromJson((p as Map).cast<String, dynamic>()))
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('../../run/fixtures/free_barometer_v3.json').readAsStringSync(),
  ) as Map;
  for (final c in fixture['cases'] as List) {
    test('live/final elevation share filtering: ${c['name']}', () {
      final source = inputs(c['inputs']);
      final calc = r.RunCalculator();
      final seen = <r.RunInput>[];
      for (final p in source) {
        seen.add(p);
        calc.add(p);
        final live = calc.liveElevationStats(seen);
        expect(
          live.elevationGainM == null || live.elevationGainM!.isFinite,
          true,
        );
        expect(identical(live, calc.liveElevationStats(seen)), true);
        if (p.kind == r.RunKind.pause) {
          expect(live.elevationGainM, calc.resultStats(seen).elevationGainM);
        }
      }
      expect(
        calc.liveElevationStats(seen).toJson(),
        calc.resultStats(seen).toJson(),
      );
    });
  }
  test('recording UI receives provisional elevation before END and resets on a new run', () async {
    final gps = fake.TestLocation();
    final driver = RunController(
      fake.FailingStore(),
      gps,
      fake.TestApi(),
      () async => 'alice',
      automaticTicks: false,
      nowMs: gps.nowMs,
    );
    final ui = FreeRunController.recording(driver);
    driver.currentOwner = 'alice';
    try {
      final source = inputs((fixture['cases'] as List).first['inputs']);
      final seen = source
          .where((p) => p.kind != r.RunKind.end && p.kind != r.RunKind.pause)
          .toList();
      driver.recorder.current = r.LocalRun(
        id: 'live',
        owner: 'alice',
        startedAt: fake.epoch,
        inputs: seen,
      );
      driver.recorder.calculator = r.RunCalculator.replay(seen);
      driver.recorder.elapsedMs = seen.last.elapsedMs;
      final run = ui.snapshot;
      expect(run.state, RunState.running);
      expect(run.liveElevationGainM, isNotNull);
      expect(run.resultStats, isNull);
      final begin = source.first;
      driver.recorder.current = r.LocalRun(
        id: 'next',
        owner: 'alice',
        startedAt: fake.epoch,
        inputs: [begin],
      );
      driver.recorder.calculator = r.RunCalculator()..add(begin);
      driver.recorder.elapsedMs = 0;
      expect(ui.snapshot.liveElevationGainM, isNull);
    } finally {
      ui.dispose();
      driver.recorder.current = null;
      await driver.shutdown();
      driver.dispose();
    }
  });
  testWidgets(
    'all-metrics elevation updates in place, distinguishes no data and flat ground',
    (tester) async {
      tester.view.physicalSize = const Size(402, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> show(double? elevation) => tester.pumpWidget(
        ProviderScope(
          overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
          child: MaterialApp(
            theme: WdTheme.light(),
            home: FreeRunLiveView(
              run: RunSnapshot(
                state: RunState.running,
                sessionId: 'live',
                startedAt: fake.epoch,
                elapsed: const Duration(seconds: 30),
                active: const Duration(seconds: 30),
                distanceMeters: 90,
                inputs: const [],
                liveElevationGainM: elevation,
              ),
              onPause: () {},
              onResume: () {},
              onStop: () {},
            ),
          ),
        ),
      );
      await show(null);
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(find.text('누적 고도'), findsOneWidget);
      expect(find.text('5 m'), findsNothing);
      await show(5.4);
      await tester.pumpAndSettle();
      expect(find.text('5 m'), findsOneWidget);
      await show(8.7);
      await tester.pumpAndSettle();
      expect(find.text('9 m'), findsOneWidget);
      await show(0);
      await tester.pumpAndSettle();
      expect(find.text('0 m'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
