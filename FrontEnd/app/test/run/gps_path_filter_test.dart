import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/gps_path_filter.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/course_tracker.dart';
import 'package:wadadak/core/map/geo_point.dart';

void main() {
  final fixture = jsonDecode(
    File('../../run/fixtures/gps_path_v4.json').readAsStringSync(),
  ) as Map;
  for (final c in fixture['cases'] as List) {
    test('shared GPS path case: ${c['name']}', () {
      final raw = (c['inputs'] as List)
          .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
          .toList();
      final before = jsonEncode(raw.map((p) => p.toJson()).toList());
      final filter = GpsPathFilter();
      final filtered = raw.expand(filter.add).toList();
      expect(filtered.length, raw.length);
      for (var i = 0; i < raw.length; i++) {
        expect(filtered[i].seq, raw[i].seq);
        expect(filtered[i].elapsedMs, raw[i].elapsedMs);
        expect(filtered[i].measuredAt, raw[i].measuredAt);
        expect(filtered[i].kind, raw[i].kind);
        expect(filtered[i].speedMps, raw[i].speedMps);
        if (raw[i].kind != RunKind.gps) {
          expect(filtered[i].toJson(), raw[i].toJson());
        }
      }
      expect(jsonEncode(raw.map((p) => p.toJson()).toList()), before);
      final gps = filtered.where((p) => p.kind == RunKind.gps).toList();
      switch (c['behavior']) {
        case 'stationary':
          for (final p in gps) {
            expect(p.distanceTo(gps.first), lessThan(1e-6));
          }
        case 'unchanged':
          expect(
            filtered.map((p) => p.toJson()).toList(),
            raw.map((p) => p.toJson()).toList(),
          );
        case 'spike':
          expect(gps[10].lat, closeTo(37, 1e-9));
        case 'smoother':
          var original = 0.0, clean = 0.0;
          final rawGps = raw.where((p) => p.kind == RunKind.gps).toList();
          for (var i = 1; i < gps.length; i++) {
            original += rawGps[i - 1].distanceTo(rawGps[i]);
            clean += gps[i - 1].distanceTo(gps[i]);
          }
          expect(clean, lessThan(original * .98));
      }
      if (c['behavior'] == 'long') {
        final calc = RunCalculator.replay(raw);
        expect(calc.distanceM, inInclusiveRange(1240, 1280));
        final route = <GeoPoint>[];
        final breaks = <int>[];
        for (final segment in calc.segments) {
          if (segment.length < 2) continue;
          if (route.isNotEmpty) breaks.add(route.length);
          route.addAll(segment.map((p) => GeoPoint(p.lat!, p.lng!)));
        }
        final tracker = CourseTracker(
          RouteGeometry(route, breaks: breaks),
          freeGhostV2: true,
        );
        for (var i = 1; i <= raw.length; i++) {
          tracker.feed(raw.sublist(0, i));
        }
        expect(
          tracker.recognizedM / RouteGeometry(route, breaks: breaks).length,
          greaterThanOrEqualTo(.95),
        );
        expect(
          calc.at(raw.last.elapsedMs).movingMs,
          lessThan(calc.at(raw.last.elapsedMs).activeMs - 100000),
        );
      }
    });
  }
  test('export shared metrics for app/server parity', () {
    final report = <Map<String, dynamic>>[];
    for (final c in fixture['cases'] as List) {
      final raw = (c['inputs'] as List)
          .map((p) => RunInput.fromJson((p as Map).cast<String, dynamic>()))
          .toList();
      final filter = GpsPathFilter();
      final filtered = raw.expand(filter.add).toList();
      final calc = RunCalculator.replay(raw);
      report.add({
        'name': c['name'],
        'inputs': filtered.map((p) => p.toJson()).toList(),
        'distanceM': calc.distanceM,
        'movingMs': calc.at(raw.last.elapsedMs).movingMs,
        'elapsedMs': calc.at(raw.last.elapsedMs).elapsedMs,
      });
    }
    Directory('build').createSync(recursive: true);
    File('build/gps-path-v4-parity.json').writeAsStringSync(jsonEncode(report));
  });
}
