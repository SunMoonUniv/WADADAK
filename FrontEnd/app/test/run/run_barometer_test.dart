import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/application/free_run_controller.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

import 'recording/run_controller_test.dart' as fake;
import 'run_device_controller_test.dart' as devices;

class PressureDevice extends devices.Device {
  bool hasPressure = true, failSample = false;
  int pressureStarts = 0, pressureStops = 0;
  Map<String, dynamic>? pressure;
  @override
  Future<bool> startPressure() async {
    pressureStarts++;
    return hasPressure;
  }

  @override
  Future<Map<String, dynamic>?> samplePressure() async {
    if (failSample) throw StateError('pressure sensor disconnected');
    final result = pressure;
    pressure = null;
    return result;
  }

  @override
  Future<void> stopPressure() async {
    pressureStops++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  final fixture = jsonDecode(
    File('../../run/fixtures/free_barometer_v3.json').readAsStringSync(),
  ) as Map;
  for (final c in fixture['cases'] as List) {
    test('shared barometer app/server: ${c['name']}', () {
      final inputs = (c['inputs'] as List)
          .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
          .toList();
      final calc = RunCalculator.replay(inputs);
      final actual = calc.resultStats(inputs).toJson();
      final expected = c['expected'] as Map;
      for (final key in expected.keys) {
        expect(
          actual[key],
          expected[key] is num
              ? closeTo(expected[key], .000001)
              : expected[key],
          reason: key,
        );
      }
      // Adding sensor events cannot change motion, route, cadence or best pace.
      final withoutPressure = inputs
          .where((p) => p.kind != RunKind.barometer)
          .toList();
      final original = RunCalculator.replay(withoutPressure);
      expect(
        calc.at(inputs.last.elapsedMs).toJson(),
        original.at(inputs.last.elapsedMs).toJson(),
      );
      expect(
        calc.lapsAt(inputs.last.elapsedMs).map((p) => p.toJson()),
        original.lapsAt(inputs.last.elapsedMs).map((p) => p.toJson()),
      );
      expect(
        calc.segments.map((s) => s.map((p) => p.toJson())),
        original.segments.map((s) => s.map((p) => p.toJson())),
      );
      final originalStats = original.resultStats(withoutPressure);
      expect(
        actual['bestPaceSecondsPerKm'],
        originalStats.bestPaceSecondsPerKm,
      );
      expect(actual['bestLapNumber'], originalStats.bestLapNumber);
      expect(
        inputs.map((p) => RunInput.fromJson(p.toJson()).toJson()),
        inputs.map((p) => p.toJson()),
      );
    });
  }

  test('recorder preserves raw sample clock and rejects stale, duplicate, future and pre-resume samples', () async {
    final store = fake.FailingStore();
    var clock = 100000;
    final recorder = RunRecorder(store, () async => clock);
    try {
      await recorder.start('pressure-clock', 'alice', fake.epoch);
      clock += 1000;
      await recorder.barometer(1000, 3, sampleClockMs: clock);
      await recorder.barometer(999, 3, sampleClockMs: clock); // duplicate
      await recorder.barometer(999, 3, sampleClockMs: clock + 1); // future
      await recorder.barometer(double.nan, 3, sampleClockMs: clock);
      await recorder.barometer(999, 4, sampleClockMs: clock);
      clock += 5000;
      await recorder.barometer(999, 3, sampleClockMs: clock - 3000); // stale
      await recorder.pause();
      clock += 1000;
      await recorder.barometer(999, 3, sampleClockMs: clock); // paused
      await recorder.resume();
      await recorder.barometer(
        999,
        3,
        sampleClockMs: clock - 500,
      ); // before resume
      clock += 1000;
      await recorder.barometer(999, 0, sampleClockMs: clock - 500);
      final pressure = recorder.current!.inputs
          .where((p) => p.kind == RunKind.barometer)
          .toList();
      expect(pressure.length, 2);
      expect(pressure.first.pressureHpa, 1000);
      expect(pressure.first.sampleEndMs, 1000);
      expect(pressure.last.sampleEndMs, 7500);
      expect(pressure.last.elapsedMs, 8000);
      expect(
        pressure.last.pressureAccuracy,
        0,
      ); // preserve raw unreliable status
      final saved = (await store.list('alice', id: 'pressure-clock')).single;
      expect(
        saved.inputs.map((p) => p.toJson()),
        recorder.current!.inputs.map((p) => p.toJson()),
      );
    } finally {
      await recorder.close();
      await store.close();
    }
  });

  for (final supported in [true, false]) {
    test(
      'controller pressure supported=$supported; step sensor absence and pressure failure never stop GPS',
      () async {
        final store = fake.FailingStore();
        final gps = fake.TestLocation();
        final device = PressureDevice()
          ..supported = false
          ..hasPressure = supported;
        final c = RunController(
          store,
          gps,
          fake.TestApi(),
          () async => 'alice',
          device: device,
          automaticTicks: false,
          wait: (_) async {},
          utcNow: () => gps.utc,
          nowMs: gps.nowMs,
          lifecycleState: () => AppLifecycleState.resumed,
        );
        final ui = FreeRunController.recording(c);
        try {
          await c.prepareStart();
          await fake.until(() => device.pressureStarts == 1);
          gps.clock = 1000;
          device.pressure = {
            'pressureHpa': 1000.25,
            'pressureAccuracy': 3,
            'sampleClockMs': 900,
          };
          await c.refreshMeasurement();
          expect(
            c.run!.inputs.where((p) => p.kind == RunKind.barometer).length,
            supported ? 1 : 0,
          );
          device.failSample = true;
          gps.clock = 2000;
          await c.refreshMeasurement();
          expect(c.run!.phase, RunPhase.running);
          expect(c.storageFault, false);
          expect(ui.snapshot.elapsed.inMilliseconds, c.metrics.elapsedMs);
          await c.pause();
          final count = c.run!.inputs
              .where((p) => p.kind == RunKind.barometer)
              .length;
          expect(device.pressureStops, greaterThan(0));
          device.failSample = false;
          device.pressure = {
            'pressureHpa': 999,
            'pressureAccuracy': 3,
            'sampleClockMs': 2500,
          };
          gps.clock = 3000;
          await c.refreshMeasurement();
          expect(
            c.run!.inputs.where((p) => p.kind == RunKind.barometer).length,
            count,
          );
          device.pressure = null;
          await c.resume();
          await fake.until(() => device.pressureStarts == 2);
          await c.pause();
          await c.end();
          expect(c.run!.phase, RunPhase.ended);
        } finally {
          ui.dispose();
          await c.shutdown();
          c.dispose();
          for (final stream in gps.streams) {
            await stream.close();
          }
        }
      },
    );
  }
}
