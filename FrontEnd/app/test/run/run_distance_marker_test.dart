import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/recording_models.dart' as recording;
import 'package:wadadak/features/run/domain/run_distance_marker.dart';
import 'package:wadadak/features/run/domain/run_models.dart';

const metresPerDegree = 6371008.8 * math.pi / 180;
RunPoint point(double metres) => RunPoint(36 + metres / metresPerDegree, 127);
RunSnapshot snapshot(double distance, List<List<RunPoint>> segments) =>
    RunSnapshot(
      state: RunState.running,
      sessionId: 'markers',
      startedAt: DateTime.utc(2026, 10, 20),
      elapsed: const Duration(seconds: 30),
      active: const Duration(seconds: 30),
      distanceMeters: distance,
      inputs: const [],
      segments: segments,
    );

void main() {
  test('no future marker from rounded display distance, missing route or isolated fixes', () {
    expect(
      runDistanceMarkers(
        snapshot(999.6, [
          [point(0), point(1000)],
        ]),
      ),
      isEmpty,
    );
    expect(runDistanceMarkers(snapshot(3000, [])), isEmpty);
    expect(
      runDistanceMarkers(
        snapshot(3000, [
          [point(0)],
          [],
          [point(10000)],
        ]),
      ),
      isEmpty,
    );
    expect(
      runDistanceMarkers(
        snapshot(double.nan, [
          [point(0), point(2000)],
        ]),
      ),
      isEmpty,
    );
  });
  test('exact kilometres, multiple boundaries and a partial lap', () {
    for (final metres in [1000.0, 2500.0, 3000.0]) {
      final markers = runDistanceMarkers(
        snapshot(metres, [
          [point(0), point(metres)],
        ]),
      );
      expect(markers.map((m) => m.km), [
        for (var km = 1; km <= metres ~/ 1000; km++) km,
      ]);
      for (final marker in markers) {
        expect(
          marker.point.distanceTo(point(marker.km * 1000.0)),
          lessThan(.00001),
        );
      }
    }
  });
  test('authoritative distance caps markers and incomplete geometry never invents a position', () {
    expect(
      runDistanceMarkers(
        snapshot(1500, [
          [point(0), point(3500)],
        ]),
      ).length,
      1,
    );
    expect(
      runDistanceMarkers(
        snapshot(3500, [
          [point(0), point(1500)],
        ]),
      ).length,
      1,
    );
  });
  test('carry valid metres across separated segments but never count or interpolate the gap', () {
    final route = [
      [point(0), point(900)],
      <RunPoint>[],
      [point(10000), point(10200)],
    ];
    final before = route
        .map((s) => s.map((p) => [p.latitude, p.longitude]).toList())
        .toList();
    final markers = runDistanceMarkers(snapshot(1100, route));
    expect(markers.single.km, 1);
    expect(markers.single.point.distanceTo(point(10100)), lessThan(.00001));
    expect(
      route
          .map((s) => s.map((p) => [p.latitude, p.longitude]).toList())
          .toList(),
      before,
    );
  });
  test('duplicate fixes, empty segments and invalid points do not create connecting edges', () {
    final route = [
      [
        point(0),
        point(0),
        point(500),
        RunPoint(double.nan, 127),
        point(800),
        point(1400),
      ],
    ];
    final marker = runDistanceMarkers(snapshot(1100, route)).single;
    expect(marker.point.distanceTo(point(1300)), lessThan(.00001));
  });
  test(
    'returning to the same physical place keeps separate kilometre labels',
    () {
      final markers = runDistanceMarkers(
        snapshot(3000, [
          [point(0), point(1000), point(0), point(1000)],
        ]),
      );
      expect(markers.map((m) => m.km), [1, 2, 3]);
      expect(
        markers.first.point.distanceTo(markers.last.point),
        lessThan(.00001),
      );
    },
  );
  test('an antimeridian edge places markers on the short route', () {
    final markers = runDistanceMarkers(
      snapshot(4000, [
        [const RunPoint(0, 179.98), const RunPoint(0, -179.98)],
      ]),
    );
    expect(markers.length, 4);
    expect(markers.every((m) => m.point.longitude.abs() > 179.9), true);
  });

  for (final boundary in ['gap', 'pause', 'jump', 'long-gap', 'bad-fix']) {
    test(
      'real PACE_V3 $boundary: marker agrees with laps, recovery and accepted segments',
      () {
        final raw = <recording.RunInput>[];
        final epoch = DateTime.utc(2026, 10, 20);
        void add(
          recording.RunKind kind,
          int ms, {
          double? metres,
          double accuracy = 3,
        }) {
          raw.add(
            recording.RunInput(
              seq: raw.length,
              kind: kind,
              elapsedMs: ms,
              measuredAt: epoch.add(Duration(milliseconds: ms)),
              reason: kind == recording.RunKind.start ? 'PACE_V3' : null,
              lat: metres == null ? null : point(metres).latitude,
              lng: metres == null ? null : 127,
              accuracyM: metres == null ? null : accuracy,
              speedMps: metres == null ? null : 3,
              speedAccuracyMps: metres == null ? null : .1,
            ),
          );
        }

        add(recording.RunKind.start, 0);
        for (var i = 0; i <= 300; i++) {
          add(recording.RunKind.gps, i * 1000, metres: i * 3);
        }
        var nextMs = 302000;
        switch (boundary) {
          case 'gap':
            add(recording.RunKind.gap, 301000);
          case 'pause':
            add(recording.RunKind.pause, 301000);
            add(recording.RunKind.gps, 301500, metres: 500000);
            add(recording.RunKind.resume, 302000);
            nextMs = 303000;
          case 'jump':
            add(recording.RunKind.gps, 301000, metres: 500000);
          case 'long-gap':
            nextMs = 312001;
          case 'bad-fix':
            add(recording.RunKind.gps, 301000, metres: 500000, accuracy: 100);
        }
        for (var i = 0; i <= 400; i++) {
          add(recording.RunKind.gps, nextMs + i * 1000, metres: 10000 + i * 3);
        }
        final calc = recording.RunCalculator.replay(raw);
        RunSnapshot from(recording.RunCalculator c) => snapshot(
          c.distanceM,
          c.segments
              .map((s) => s.map((p) => RunPoint(p.lat!, p.lng!)).toList())
              .toList(),
        );
        final original = raw.map((p) => p.toJson()).toList();
        final metrics = calc.at(raw.last.elapsedMs).toJson();
        final laps = calc
            .lapsAt(raw.last.elapsedMs)
            .map((p) => p.toJson())
            .toList();
        final markers = runDistanceMarkers(from(calc));
        expect(markers.map((m) => m.km), [1, 2]);
        expect(calc.segments.length, 2);
        expect(
          markers.length,
          calc.lapsAt(raw.last.elapsedMs).where((l) => l.complete).length,
        );
        expect(markers[0].point.distanceTo(point(10100)), lessThan(.001));
        expect(markers[1].point.distanceTo(point(11100)), lessThan(.001));
        final restored = runDistanceMarkers(
          from(recording.RunCalculator.replay(raw)),
        );
        expect(
          restored
              .map((m) => [m.km, m.point.latitude, m.point.longitude])
              .toList(),
          markers
              .map((m) => [m.km, m.point.latitude, m.point.longitude])
              .toList(),
        );
        expect(raw.map((p) => p.toJson()).toList(), original);
        expect(calc.at(raw.last.elapsedMs).toJson(), metrics);
        expect(
          calc.lapsAt(raw.last.elapsedMs).map((p) => p.toJson()).toList(),
          laps,
        );
      },
    );
  }
}
