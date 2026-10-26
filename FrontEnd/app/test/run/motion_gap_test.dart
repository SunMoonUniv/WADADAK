import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

void main() {
  final fixture = jsonDecode(
    File('../../run/fixtures/motion_gap_null_v1.json').readAsStringSync(),
  ) as Map;
  for (final c in fixture['cases'] as List) {
    test('shared nullable GAP boundary: ${c['name']}', () {
      final raw = (c['inputs'] as List)
          .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
          .toList();
      final before = jsonEncode(raw.map((p) => p.toJson()).toList());
      final expected = c['expected'] as Map;
      final actual = RunCalculator.replay(raw);
      final metrics = actual.at(raw.last.elapsedMs);
      expect(metrics.distanceM, closeTo(expected['distanceM'] as num, .000001));
      expect(metrics.elapsedMs, expected['elapsedMs']);
      expect(metrics.activeMs, expected['activeMs']);
      expect(metrics.movingMs, expected['movingMs']);
      expect(metrics.gapCount, expected['gapCount']);
      expect(
        actual.segments.map((s) => s.map((p) => p.elapsedMs).toList()).toList(),
        expected['segmentMs'],
      );
      final laps = actual.lapsAt(raw.last.elapsedMs);
      expect(laps, hasLength(1));
      expect(laps.single.distanceM, closeTo(metrics.distanceM, .000001));
      expect(laps.single.movingMs, metrics.movingMs);
      expect(laps.single.elapsedMs, metrics.elapsedMs);
      expect(jsonEncode(raw.map((p) => p.toJson()).toList()), before);
    });
  }
}
