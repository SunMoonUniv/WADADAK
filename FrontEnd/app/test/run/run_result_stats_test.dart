import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/run_result_stats.dart';
import 'package:wadadak/features/run/application/run_result_mapper.dart';

void main() {
  final fixture = jsonDecode(
    File('../../run/fixtures/free_result_stats_v2.json').readAsStringSync(),
  ) as Map;
  for (final c in fixture['cases'] as List) {
    test('shared app/server result: ${c['name']}', () {
      final inputs = (c['inputs'] as List)
          .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
          .toList();
      final calc = RunCalculator.replay(inputs);
      final actual = calc.resultStats(inputs).toJson();
      final expected = c['expected'] as Map;
      for (final key in expected.keys) {
        final value = expected[key];
        expect(
          actual[key],
          value is num ? closeTo(value, .000001) : value,
          reason: '$key in ${c['name']}',
        );
      }
      expect(RunResultStats.fromJson(actual).toJson(), actual);
      expect(
        identical(calc.resultStats(inputs), calc.resultStats(inputs)),
        isTrue,
      );
      final withoutAltitude = inputs
          .map(
            (p) => RunInput.fromJson(
              {...p.toJson()}
                ..remove('altitudeM')
                ..remove('altitudeAccuracyM'),
            ),
          )
          .toList();
      final original = RunCalculator.replay(withoutAltitude);
      expect(
        calc.at(inputs.last.elapsedMs).toJson(),
        original.at(inputs.last.elapsedMs).toJson(),
      );
      expect(
        calc.lapsAt(inputs.last.elapsedMs).map((l) => l.toJson()),
        original.lapsAt(inputs.last.elapsedMs).map((l) => l.toJson()),
      );
    });
  }
  test('remote and pre-feature result JSON remain readable', () {
    final result = <String, dynamic>{
      'id': 'saved',
      'startedAt': '2026-10-16T00:00:00Z',
      'metrics': {'distanceM': 1200, 'elapsedMs': 400000, 'activeMs': 390000},
    };
    expect(remoteRunSnapshot(result).resultStats, isNull);
    expect(
      RunResultStats.fromJson({'version': 'RESULT_V1', 'elevationGainM': 0})
          .version,
      'RESULT_V1',
    );
    expect(
      RunResultStats.fromJson({'version': 'RESULT_V1', 'elevationGainM': 0})
          .toJson()['version'],
      'RESULT_V1',
    );
    const stats = RunResultStats(
      elevationGainM: 42,
      bestLapNumber: 1,
      bestLapPaceSecondsPerKm: 300,
      bestPaceSecondsPerKm: 270,
    );
    expect(
      remoteRunSnapshot({...result, 'stats': stats.toJson()}).resultStats!
          .toJson(),
      stats.toJson(),
    );
  });
}
