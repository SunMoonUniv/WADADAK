import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';
import 'package:wadadak/features/run/application/run_sensor_session.dart';
import 'package:wadadak/features/run/data/run_device.dart';
import 'package:wadadak/features/run/domain/free_run_session.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/domain/recording_models.dart' as recording;
import 'package:wadadak/features/run/presentation/free_run_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'ghost_recovery_support.dart';
import 'recording/run_controller_test.dart' show FailingStore;

class CountingController extends FreeRunController {
  CountingController(FreeRunSession session)
    : super(createSession: () => session, createId: () => 'synthetic-run');
  int comparisons = 0;
  @override
  ({GeoPoint? position, String distance, String time}) get ghostComparison {
    comparisons++;
    return (position: null, distance: '10m 앞서요', time: '2초 앞서요');
  }
}

class DelayedDevice extends RunDevice {
  final steps = Completer<Map<String, dynamic>?>();
  final pressure = Completer<Map<String, dynamic>?>();
  @override
  Future<String> startSteps() async => '센서 미지원';
  @override
  Future<bool> startPressure() async => true;
  @override
  Future<Map<String, dynamic>?> sampleSteps({bool force = false}) =>
      steps.future;
  @override
  Future<Map<String, dynamic>?> samplePressure() => pressure.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'receipt stays defensive while validated replay is reused unchanged',
    () {
      final intent = ghostIntent();
      final approval = ghostApproval(intent);
      final context = GhostRunContext(intent, approval);
      final before = jsonEncode(context.toJson());
      final replay = context.replay;
      (approval['playback'] as Map)['durationMs'] = 1;
      (context.approval['playback'] as Map)['durationMs'] = 2;
      expect(identical(context.replay, replay), isTrue);
      expect(context.replay.playback.durationMs, intent.sourceSeconds * 1000);
      expect(jsonEncode(context.toJson()), before);
      final restored = GhostRunContext.fromJson(context.toJson());
      expect(restored.replay.payloadJson, replay.payloadJson);
      expect(identical(restored.replay, restored.replay), isTrue);
    },
  );

  testWidgets(
    'one live rebuild computes comparison once; ready and result do not',
    (tester) async {
      final session = FreeRunSession(
        monotonicNow: () => Duration.zero,
        utcNow: () => DateTime.utc(2026, 11, 2),
      );
      final controller = CountingController(session);
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            freeRunControllerProvider.overrideWithValue(controller),
            mapEngineProvider.overrideWithValue(MapEngine.dev),
          ],
          child: MaterialApp(
            theme: WdTheme.light(),
            home: const FreeRunScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.comparisons, 0);
      session.start('synthetic-run');
      controller.notifyListeners();
      await tester.pumpAndSettle();
      final previous = controller.comparisons;
      controller.notifyListeners();
      await tester.pump();
      expect(controller.comparisons - previous, 1);
      session.pause();
      controller.notifyListeners();
      await tester.pump();
      expect(controller.comparisons - previous, 2);
      session.finish();
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(controller.comparisons - previous, 2);
    },
  );

  for (final pressure in [false, true]) {
    test(
      'late ${pressure ? 'pressure' : 'step'} sample cannot enter a different or stopped run',
      () async {
        final store = FailingStore();
        final recorder = RunRecorder(store, () async => 0);
        final device = DelayedDevice();
        var allowed = true;
        final sensors = RunSensorSession(
          device,
          recorder,
          canSample: (id) => allowed && id == 'synthetic-run',
        );
        try {
          await recorder.start(
            'synthetic-run',
            'alice',
            DateTime.utc(2026, 11, 2),
          );
          await sensors.start('synthetic-run');
          expect(sensors.cadenceStatus, '센서 미지원');
          final pending = pressure
              ? sensors.samplePressure()
              : sensors.sampleCadence();
          allowed = false;
          if (pressure) {
            device.pressure.complete({
              'pressureHpa': 1000,
              'pressureAccuracy': 3,
              'sampleClockMs': 1000,
            });
          } else {
            device.steps.complete({
              'steps': 20,
              'durationMs': 5000,
              'sampleEndClockMs': 5000,
            });
          }
          await pending;
          expect(
            recorder.current!.inputs.where(
              (i) =>
                  i.kind == recording.RunKind.cadence ||
                  i.kind == recording.RunKind.barometer,
            ),
            isEmpty,
          );
        } finally {
          await recorder.close();
          await store.close();
        }
      },
    );
  }
}
