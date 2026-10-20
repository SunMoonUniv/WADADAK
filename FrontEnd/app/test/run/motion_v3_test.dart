import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

List<RunInput> inputs(dynamic json) => (json as List)
    .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
    .toList();
void main() {
  final fixture = jsonDecode(
    File('../../run/fixtures/free_motion_v3.json').readAsStringSync(),
  ) as Map;
  for (final c in fixture['cases'] as List) {
    test('balanced app/server scenario: ${c['name']}', () {
      final raw = inputs(c['inputs']);
      final before = jsonEncode(raw.map((p) => p.toJson()).toList());
      final actual = RunCalculator.replay(raw);
      final reference = RunCalculator.replay(inputs(c['reference']));
      expect(actual.distanceM, closeTo(reference.distanceM, .000001));
      expect(
        actual.at(raw.last.elapsedMs).movingMs,
        reference.at(raw.last.elapsedMs).movingMs,
      );
      expect(
        actual.segments.map((s) => s.map((p) => p.elapsedMs).toList()).toList(),
        reference.segments
            .map((s) => s.map((p) => p.elapsedMs).toList())
            .toList(),
      );
      expect(
        actual.resultStats(raw).elevationGainM,
        reference.resultStats(inputs(c['reference'])).elevationGainM,
      );
      expect(jsonEncode(raw.map((p) => p.toJson()).toList()), before);
      // A soft-filtered fix must never conceal a hard boundary in raw GPS.
      final gps = raw.where((p) => p.kind == RunKind.gps).toList();
      for (var i = 1; i < gps.length; i++) {
        final a = gps[i - 1], b = gps[i];
        final dt = b.elapsedMs - a.elapsedMs;
        if (a.good &&
            b.good &&
            dt > 0 &&
            (dt > 10000 || a.distanceTo(b) * 1000 / dt > 12)) {
          expect(
            actual.segments.any(
              (s) =>
                  s.first.elapsedMs <= a.elapsedMs &&
                  s.last.elapsedMs >= b.elapsedMs,
            ),
            false,
            reason: 'raw boundary ${a.elapsedMs}..${b.elapsedMs}',
          );
        }
      }
      if (c['rejectedMs'] != null) {
        expect(
          actual.segments
              .expand((s) => s)
              .any((p) => p.elapsedMs == c['rejectedMs']),
          false,
        );
      }
    });
  }
}
