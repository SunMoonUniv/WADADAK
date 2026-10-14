import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/data/run_local_store.dart';
import 'package:wadadak/features/run/application/run_recorder.dart';

final start = DateTime.utc(2026, 10, 12);
RunInput input(
  int seq,
  RunKind kind,
  int ms, {
  double? lat,
  double accuracy = 3,
}) => RunInput(
  seq: seq,
  kind: kind,
  elapsedMs: ms,
  measuredAt: start.add(Duration(milliseconds: ms)),
  lat: lat,
  lng: lat == null ? null : 127,
  accuracyM: lat == null ? null : accuracy,
);

void main() {
  test('app and server share pause fixture and elapsed-time pace', () {
    final fixture = jsonDecode(
      File('../../run/fixtures/free_pause_v1.json').readAsStringSync(),
    ) as Map;
    final records = (fixture['inputs'] as List).map(
      (j) => RunInput.fromJson((j as Map).cast<String, dynamic>()),
    );
    final result = RunCalculator.replay(records).at(120000);
    expect(result.elapsedMs, fixture['expected']['elapsedMs']);
    expect(result.activeMs, fixture['expected']['activeMs']);
    expect(
      result.distanceM,
      closeTo((fixture['expected']['distanceM'] as num).toDouble(), 0.000001),
    );
    expect(
      result.elapsedPaceSecondsPerKm,
      closeTo(120000 / result.distanceM, 0.000001),
    );
  });
  test(
    'bad fixes, long gaps, jumps and pause boundaries never bridge distance',
    () {
      final c = RunCalculator.replay([
        input(0, RunKind.start, 0),
        input(1, RunKind.gps, 0, lat: 36),
        input(2, RunKind.gps, 1000, lat: 36.00005),
        input(3, RunKind.gps, 2000, lat: 37, accuracy: 100),
        input(4, RunKind.gps, 3000, lat: 36.1),
        input(5, RunKind.gps, 14001, lat: 36.2),
        input(6, RunKind.gps, 15001, lat: 37),
        input(7, RunKind.pause, 16000),
        input(8, RunKind.gps, 17000, lat: 38),
        input(9, RunKind.resume, 18000),
        input(10, RunKind.gps, 18000, lat: 39),
        input(11, RunKind.gps, 19000, lat: 39.00005),
        input(12, RunKind.end, 20000),
      ]);
      expect(c.distanceM, closeTo(11.119508, 0.00001));
      expect(c.gapCount, 3);
      expect(c.at(20000).activeMs, 18000);
      expect(c.segments.length, 5);
    },
  );
  test(
    'stationary jitter, poor accuracy and a gap cannot automatically resume',
    () {
      final detector = RunAutoResume();
      for (var i = 0; i < 30; i++) {
        expect(
          detector.add(
            input(i, RunKind.gps, i * 1000, lat: 36 + (i % 2) * 0.000001),
          ),
          false,
        );
      }
      expect(
        detector.add(input(31, RunKind.gps, 31000, lat: 36.001, accuracy: 100)),
        false,
      );
      expect(detector.add(input(32, RunKind.gps, 32000, lat: 36.002)), false);
      expect(detector.add(input(33, RunKind.gps, 50000, lat: 36.003)), false);
    },
  );

  group('durable recorder', () {
    late RunLocalStore store;
    late RunRecorder recorder;
    var clock = 0;
    setUp(() {
      sqfliteFfiInit();
      clock = 0;
      store = RunLocalStore(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      recorder = RunRecorder(store, () async => clock, motionFiltering: false);
    });
    tearDown(() async {
      await recorder.close();
      await store.close();
    });
    test(
      'confirmed movement resumes once and does not backfill paused movement',
      () async {
        await recorder.start('run', 'alice', start);
        await recorder.gps(36, 127, 3);
        clock = 1000;
        await recorder.gps(36.00005, 127, 3);
        await recorder.pause();
        clock = 2000;
        await recorder.gps(36.01, 127, 3);
        clock = 3000;
        await recorder.gps(36.01005, 127, 3);
        clock = 4000;
        await recorder.gps(36.0101, 127, 3);
        expect(recorder.current!.phase, RunPhase.running);
        expect(
          recorder.current!.inputs
              .where((p) => p.kind == RunKind.resume)
              .length,
          1,
        );
        expect(recorder.metrics.distanceM, closeTo(5.559754, 0.00001));
        clock = 5000;
        await recorder.gps(36.01015, 127, 3);
        expect(recorder.metrics.distanceM, closeTo(11.119508, 0.00001));
        final loaded = (await store.list('alice')).single;
        expect(
          loaded.inputs.map((p) => p.seq),
          List.generate(loaded.inputs.length, (i) => i),
        );
        expect(loaded.phase, RunPhase.running);
      },
    );
    test(
      'invalid coordinates break the route without storing non-JSON numbers',
      () async {
        await recorder.start('run', 'alice', start);
        await recorder.gps(36, 127, 3);
        clock = 1000;
        await recorder.gps(36.00005, 127, 3);
        clock = 2000;
        await recorder.gps(double.nan, 127, 3);
        expect(recorder.current!.inputs.last.reason, 'INVALID_FIX');
        clock = 3000;
        await recorder.gps(36.001, 127, 3);
        clock = 4000;
        await recorder.gps(36.00105, 127, 3);
        expect(recorder.metrics.distanceM, closeTo(11.119508, 0.00001));
        expect(recorder.metrics.gapCount, 1);
        final saved = (await store.list('alice')).single;
        expect(
          saved.inputs.every((p) => p.lat == null || p.lat!.isFinite),
          true,
        );
      },
    );
    test('ending confirmation holds auto-resume and late fixes after END are ignored', () async {
      await recorder.start('run', 'alice', start);
      await recorder.pause();
      recorder.confirmingEnd = true;
      for (var i = 0; i < 4; i++) {
        clock = 1000 + i * 1000;
        await recorder.gps(36 + i * 0.0001, 127, 3);
      }
      expect(recorder.current!.phase, RunPhase.paused);
      await recorder.end();
      final size = recorder.current!.inputs.length;
      clock = 10000;
      await recorder.gps(37, 127, 3);
      expect(recorder.current!.inputs.length, size);
      expect(recorder.current!.pending, false);
    });
    test('restart ends at checkpoint without inventing time and separates accounts', () async {
      await recorder.start('run', 'alice', start);
      await recorder.gps(36, 127, 3);
      clock = 1000;
      await recorder.gps(36.00005, 127, 3);
      clock = 5000;
      await recorder.tick(persist: true);
      await recorder.close();
      recorder = RunRecorder(store, () async => 999999, motionFiltering: false);
      final recovered = (await recorder.recover('alice')).single;
      expect(recovered.phase, RunPhase.ended);
      expect(recovered.inputs.last.elapsedMs, 5000);
      expect(recovered.endReason, 'INTERRUPTED');
      expect(recovered.pending, true);
      expect(await store.list('bob'), isEmpty);
    });
    test(
      'failed append rolls back inserted inputs and cannot change saved state',
      () async {
        await recorder.start('run', 'alice', start);
        await recorder.pause();
        await recorder.end();
        final before = (await store.list('alice')).single;
        await expectLater(
          store.append(
            before,
            [input(before.inputs.length, RunKind.gps, 1000, lat: 36)],
            RunPhase.running,
            1000,
          ),
          throwsStateError,
        );
        final after = (await store.list('alice')).single;
        expect(after.inputs.length, before.inputs.length);
        expect(after.phase, RunPhase.ended);
      },
    );
  });
}
