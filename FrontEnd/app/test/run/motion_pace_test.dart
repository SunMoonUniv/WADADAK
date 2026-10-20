import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

RunInput fix(
  int ms,
  double metres, {
  double accuracy = 3,
  double? speed,
  double? speedAccuracy,
}) => RunInput(
  seq: ms,
  kind: RunKind.gps,
  elapsedMs: ms,
  measuredAt: DateTime.utc(2026).add(Duration(milliseconds: ms)),
  lat: 36 + metres / 111195.0802335,
  lng: 127,
  accuracyM: accuracy,
  speedMps: speed,
  speedAccuracyMps: speedAccuracy,
);
RunInput event(RunKind kind, int ms) => RunInput(
  seq: ms,
  kind: kind,
  elapsedMs: ms,
  measuredAt: DateTime.utc(2026),
  reason: kind == RunKind.start ? 'PACE_V2' : null,
);
RunCalculator movingRun() {
  final c = RunCalculator()..add(event(RunKind.start, 0));
  for (var i = 0; i <= 10; i++) {
    c.add(fix(i * 1000, i * 3));
  }
  return c;
}

void main() {
  test(
    'reliable zero speed prevents coherent GPS drift from becoming distance',
    () {
      final c = RunCalculator()..add(event(RunKind.start, 0));
      for (var i = 0; i <= 30; i++) {
        c.add(fix(i * 1000, i * .8, speed: 0, speedAccuracy: .1));
      }
      expect(c.distanceM, 0);
      expect(c.at(30000).currentPaceSecondsPerKm, isNull);
    },
  );
  test('reliable running speed preserves a short turn instead of losing its distance', () {
    final c = RunCalculator()..add(event(RunKind.start, 0));
    c.add(fix(0, 0, speed: 3, speedAccuracy: .1));
    c.add(fix(1000, 3, speed: 3, speedAccuracy: .1));
    c.add(fix(2000, 0, speed: 3, speedAccuracy: .1));
    expect(c.distanceM, closeTo(6, .001));
  });
  test(
    'slow departure without speed metadata is not trapped in stationary state',
    () {
      final c = RunCalculator()..add(event(RunKind.start, 0));
      for (var i = 0; i <= 10; i++) {
        c.add(fix(i * 1000, 0));
      }
      expect(c.at(10000).stationary, true);
      for (var i = 11; i <= 30; i++) {
        c.add(fix(i * 1000, (i - 10) * .6));
      }
      expect(c.at(30000).stationary, false);
      expect(c.at(30000).movingMs, 20000);
      expect(c.distanceM, closeTo(12, .001));
    },
  );
  test(
    'shared v2 fixture matches server distance, moving time and elapsed pace',
    () {
      final f = jsonDecode(
        File('../../run/fixtures/free_motion_v2.json').readAsStringSync(),
      ) as Map;
      final c = RunCalculator.replay(
        (f['inputs'] as List).map(
          (p) => RunInput.fromJson((p as Map).cast<String, dynamic>()),
        ),
      );
      final m = c.at(30000);
      expect(m.distanceM, closeTo(30, .001));
      expect(m.movingMs, 10000);
      expect(m.activeMs, 30000);
      expect(m.elapsedMs, 30000);
      expect(m.paceSecondsPerKm, closeTo(1000 / 3, .01));
      expect(m.elapsedPaceSecondsPerKm, closeTo(1000, .01));
    },
  );
  test('standing GPS jitter never creates distance, route or current pace', () {
    final c = RunCalculator()..add(event(RunKind.start, 0));
    for (var i = 0; i <= 60; i++) {
      c.add(fix(i * 1000, (i % 3 - 1) * .8));
    }
    final m = c.at(60000);
    expect(m.distanceM, 0);
    expect(m.movingMs, 0);
    expect(m.activeMs, 60000);
    expect(m.currentPaceSecondsPerKm, isNull);
    expect(m.stationary, true);
    expect(c.segments, isEmpty);
  });
  test('walking at .6m/s is retained with reliable speed evidence', () {
    final c = RunCalculator()..add(event(RunKind.start, 0));
    for (var i = 0; i <= 20; i++) {
      c.add(fix(i * 1000, i * .6, speed: .6, speedAccuracy: .1));
    }
    expect(c.at(20000).stationary, false);
    expect(c.distanceM, closeTo(12, .001));
    expect(c.at(20000).currentPaceSecondsPerKm, closeTo(1000 / .6, .01));
  });
  test(
    'confirmed stop freezes moving average while elapsed pace continues',
    () {
      final c = movingRun();
      for (var i = 11; i <= 20; i++) {
        c.add(fix(i * 1000, 30 + (i % 2) * .5));
      }
      final before = c.at(20000);
      for (var i = 21; i <= 30; i++) {
        c.add(fix(i * 1000, 30 + (i % 2) * .5));
      }
      final after = c.at(30000);
      expect(after.distanceM, closeTo(30, .001));
      expect(after.movingMs, 10000);
      expect(after.paceSecondsPerKm, before.paceSecondsPerKm);
      expect(
        after.elapsedPaceSecondsPerKm,
        greaterThan(before.elapsedPaceSecondsPerKm!),
      );
      expect(after.currentPaceSecondsPerKm, isNull);
    },
  );
  test('missing GPS is unknown time even after a confirmed stop', () {
    final c = movingRun();
    for (var i = 11; i <= 20; i++) {
      c.add(fix(i * 1000, 30));
    }
    c.add(event(RunKind.gap, 30001));
    expect(c.at(40000).movingMs, 30000);
    expect(c.at(40000).currentPaceSecondsPerKm, isNull);
    c.add(fix(41000, 1000));
    c.add(fix(42000, 1003));
    c.add(fix(43000, 1006));
    expect(c.distanceM, closeTo(36, .001));
    expect(c.at(43000).currentPaceSecondsPerKm, isNull);
    c.add(fix(44000, 1009));
    c.add(fix(45000, 1012));
    expect(c.at(45000).currentPaceSecondsPerKm, closeTo(1000 / 3, .01));
  });
  test(
    'manual pause excludes travel and current pace starts fresh after resume',
    () {
      final c = movingRun();
      c.add(event(RunKind.pause, 10000));
      c.add(fix(15000, 1000));
      expect(c.at(20000).paceSecondsPerKm, closeTo(10000 / 30, .01));
      c.add(event(RunKind.resume, 20000));
      c.add(fix(20000, 1000));
      c.add(fix(21000, 1003));
      c.add(fix(22000, 1006));
      expect(c.distanceM, closeTo(36, .001));
      expect(c.at(22000).currentPaceSecondsPerKm, isNull);
      c.add(event(RunKind.end, 25000));
      expect(c.at(25000).activeMs, 15000);
      expect(c.at(25000).currentPaceSecondsPerKm, isNull);
      final saved = c.distanceM;
      c.add(fix(26000, 2000));
      expect(c.distanceM, saved);
    },
  );
  test(
    'poor fixes and implausible jumps reset both distance and pace windows',
    () {
      final c = movingRun();
      c.add(fix(11000, 1000, accuracy: 100));
      c.add(fix(12000, 2000));
      c.add(fix(13000, 3000));
      c.add(fix(14000, 3003));
      c.add(fix(15000, 3006));
      expect(c.distanceM, closeTo(36, .001));
      expect(c.at(15000).currentPaceSecondsPerKm, isNull);
      expect(c.gapCount, 2);
    },
  );
  test('current pace uses time/distance over clipped recent ten seconds', () {
    final c = movingRun();
    for (var i = 11; i <= 22; i++) {
      c.add(fix(i * 1000, 30 + (i - 10) * 2));
    }
    expect(c.at(22000).currentPaceSecondsPerKm, closeTo(500, .01));
    expect(c.at(22000).paceSecondsPerKm, closeTo(22000 / 54, .01));
    expect(c.at(32001).currentPaceSecondsPerKm, isNull);
  });
  test(
    'v2 raw input round trip and SQLite recovery reproduce filtered metrics',
    () async {
      sqfliteFfiInit();
      final store = RunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      var clock = 0;
      final recorder = RunRecorder(store, () async => clock);
      try {
        await recorder.start('v2', 'owner', DateTime.utc(2026));
        for (var i = 0; i <= 10; i++) {
          clock = i * 1000;
          final p = fix(clock, i * 3, speed: 3, speedAccuracy: .1);
          await recorder.gps(
            p.lat!,
            p.lng!,
            p.accuracyM!,
            speedMps: p.speedMps,
            speedAccuracyMps: p.speedAccuracyMps,
          );
        }
        for (var i = 11; i <= 20; i++) {
          clock = i * 1000;
          final p = fix(clock, 30, speed: 0, speedAccuracy: .1);
          await recorder.gps(
            p.lat!,
            p.lng!,
            p.accuracyM!,
            speedMps: 0,
            speedAccuracyMps: .1,
          );
        }
        await recorder.tick(persist: true);
        final record = (await store.list('owner')).single;
        final restored = RunCalculator.replay(record.inputs)
            .at(record.checkpointMs);
        expect(restored.movingMs, recorder.metrics.movingMs);
        expect(restored.distanceM, recorder.metrics.distanceM);
        expect(record.inputs.first.reason, 'PACE_V3');
        expect(record.inputs.last.speedMps, 0);
        final encoded = jsonEncode(
          record.inputs.map((p) => p.toJson()).toList(),
        );
        expect(encoded, contains('speedAccuracyMps'));
      } finally {
        await recorder.close();
        await store.close();
      }
    },
  );
  test(
    'legacy persisted fixture retains historical distance and elapsed metric',
    () {
      final f = jsonDecode(
        File('../../run/fixtures/free_pause_v1.json').readAsStringSync(),
      ) as Map;
      final c = RunCalculator.replay(
        (f['inputs'] as List).map(
          (p) => RunInput.fromJson((p as Map).cast<String, dynamic>()),
        ),
      );
      final m = c.at(120000);
      expect(m.distanceM, closeTo(22.239016, .000001));
      expect(m.elapsedPaceSecondsPerKm, closeTo(120000 / m.distanceM, .000001));
      expect(m.paceSecondsPerKm, closeTo(100000 / m.distanceM, .000001));
    },
  );
}
