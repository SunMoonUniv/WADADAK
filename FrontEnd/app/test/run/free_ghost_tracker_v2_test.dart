import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/features/run/domain/course_tracker.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';

void main() {
  final fixture = jsonDecode(
    File('../../run/fixtures/free_ghost_tracker_v2.json').readAsStringSync(),
  ) as Map;
  for (final c in fixture['cases'] as List) {
    test('FREE_V2 incremental/server parity: ${c['name']}', () {
      final route = RouteGeometry([
        for (final p in c['route'])
          GeoPoint((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
      ]);
      final inputs = [
        for (final p in c['inputs'])
          RunInput.fromJson((p as Map).cast<String, dynamic>()),
      ];
      final tracker = CourseTracker(route, freeGhostV2: true);
      final seen = <RunInput>[];
      for (final input in inputs) {
        seen.add(input);
        tracker.feed(seen);
      }
      final expected = c['expectedSamples'] as List;
      expect(tracker.points.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        final a = tracker.points[i], e = expected[i] as Map;
        expect(a.input.seq, e['seq'], reason: 'sample $i');
        expect(a.input.elapsedMs, e['elapsedMs']);
        expect(a.connected, e['connected'], reason: 'sample $i connection');
        expect(
          a.s,
          e['positionM'] == null
              ? isNull
              : closeTo((e['positionM'] as num).toDouble(), 1e-6),
          reason: 'sample $i position',
        );
      }
      expect(
        tracker.recognizedM,
        inInclusiveRange(c['minRecognizedM'], c['maxRecognizedM']),
      );
      final batched = CourseTracker(route, freeGhostV2: true)..feed(inputs);
      expect(
        batched.points.map((p) => (p.s, p.connected)).toList(),
        tracker.points.map((p) => (p.s, p.connected)).toList(),
      );
    });
  }
}
