import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/run_cadence.dart';
import 'package:wadadak/features/run/domain/run_voice.dart';

void main() {
  test('shared app/server fixture splits km across pause and gap without counting either displacement', () {
    final json = jsonDecode(
      File('../../run/fixtures/free_features_v3.json').readAsStringSync(),
    ) as Map;
    final inputs = (json['inputs'] as List)
        .map((j) => RunInput.fromJson((j as Map).cast<String, dynamic>()))
        .toList();
    final calc = RunCalculator.replay(inputs);
    final metrics = calc.at(580000);
    final expected = json['expected'] as Map;
    expect(metrics.distanceM, closeTo(2550, .000001));
    for (final key in [
      'elapsedMs',
      'activeMs',
      'movingMs',
      'gapCount',
      'cadenceCoverageMs',
      'steps',
      'averageCadence',
    ]) {
      expect(metrics.toJson()[key], expected[key], reason: key);
    }
    final laps = calc.lapsAt(580000);
    expect(laps.length, 3);
    for (var i = 0; i < laps.length; i++) {
      final e = expected['laps'][i] as Map;
      expect(
        laps[i].distanceM,
        closeTo((e['distanceM'] as num).toDouble(), .000001),
      );
      expect(laps[i].movingMs, e['movingMs']);
      expect(laps[i].elapsedMs, e['elapsedMs']);
      expect(laps[i].complete, e['complete']);
    }
    expect(laps.fold<int>(0, (sum, l) => sum + l.movingMs), metrics.movingMs);
    expect(laps.fold<int>(0, (sum, l) => sum + l.elapsedMs), metrics.elapsedMs);
    // Sensor events must not reset GPS confirmation windows or change historical distance.
    expect(
      RunCalculator.replay(inputs.where((p) => p.kind != RunKind.cadence))
          .distanceM,
      closeTo(metrics.distanceM, .000001),
    );
    expect(
      inputs.map((p) => RunInput.fromJson(p.toJson()).toJson()),
      inputs.map((p) => p.toJson()),
    );
  });
  test('exact kilometre has no extra zero-distance final lap', () {
    final epoch = DateTime.utc(2026, 10, 14);
    final calc = RunCalculator();
    calc.add(
      RunInput(seq: 0, kind: RunKind.start, elapsedMs: 0, measuredAt: epoch),
    );
    for (var i = 0; i <= 200; i++) {
      calc.add(
        RunInput(
          seq: i + 1,
          kind: RunKind.gps,
          elapsedMs: i * 1000,
          measuredAt: epoch.add(Duration(seconds: i)),
          lat: 36 + 5 * i / 6371008.8 * 180 / 3.141592653589793,
          lng: 127,
          accuracyM: 3,
        ),
      );
    }
    expect(calc.lapsAt(200000).length, 1);
    expect(calc.lapsAt(200000).single.complete, true);
  });
  test('sensor average uses coverage and rejects overlapping or invalid intervals; stale current cadence is unknown', () {
    final c = RunCadenceCalculator();
    expect(c.average, isNull);
    expect(c.current(5000), isNull);
    c.add(5000, 15, 5000);
    c.add(10000, 10, 5000);
    expect(c.average, 150);
    expect(c.current(10000), 150);
    c.add(10001, 20, 5000);
    c.add(12000, 30, 1000); // overlap, implausible cadence
    expect(c.coverageMs, 10000);
    expect(c.steps, 25);
    expect(c.current(20001), isNull);
    c.add(25000, 0, 5000);
    expect(c.current(25000), 0);
    expect(c.average, 100);
  });
  test('voice distance/time thresholds never repeat after rebuild, pause, settings changes or a new session', () {
    final scheduler = RunVoiceScheduler();
    const d = RunVoiceSettings();
    RunMetrics m(double distance, int active) =>
        RunMetrics(distance, active, active, 0);
    expect(scheduler.update('a', RunPhase.running, m(0, 0), d), isNull);
    expect(
      scheduler.update('a', RunPhase.running, m(1000, 300000), d),
      contains('1.00킬로미터'),
    );
    expect(scheduler.update('a', RunPhase.running, m(1000, 301000), d), isNull);
    expect(scheduler.update('a', RunPhase.paused, m(2000, 302000), d), isNull);
    expect(scheduler.update('a', RunPhase.running, m(2000, 302000), d), isNull);
    const t = RunVoiceSettings(unit: VoiceUnit.time, timeMinutes: 5);
    expect(scheduler.update('a', RunPhase.running, m(2000, 302000), t), isNull);
    expect(
      scheduler.update('a', RunPhase.running, m(2100, 600000), t),
      isNotNull,
    );
    expect(
      scheduler.update(
        'a',
        RunPhase.running,
        m(2100, 900000),
        t.copyWith(enabled: false),
      ),
      isNull,
    );
    expect(scheduler.update('a', RunPhase.running, m(2100, 900000), t), isNull);
    expect(scheduler.update('b', RunPhase.running, m(0, 0), t), isNull);
    expect(scheduler.update('b', RunPhase.running, m(0, 300000), t), isNotNull);
    expect(
      RunVoiceSettings.fromJson({'distanceKm': 0, 'timeMinutes': -1})
          .distanceKm,
      1,
    );
  });
}
