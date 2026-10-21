import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/course_tracker.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/run_models.dart' as live;
import 'package:wadadak/features/run/presentation/free_run_live_view.dart';

/// 서버 CourseTrackerTest·RouteGeometryTest와 같은 코스·사례(판정 기대값 - 2026-10-12). 앱 추적이 서버 판정과 같게 움직이는지 본다.
const lat0 = 37.5, lng0 = 127.0;

/// 로컬 평면(m, x = 동, y = 북) → 위도·경도. 원점 (37.5, 127.0)
GeoPoint geo(double x, double y) => GeoPoint(
  lat0 + y / 6371008.8 * 180 / math.pi,
  lng0 + x / (6371008.8 * math.cos(lat0 * math.pi / 180)) * 180 / math.pi,
);

RouteGeometry course(List<double> xy) =>
    RouteGeometry([for (var i = 0; i < xy.length; i += 2) geo(xy[i], xy[i + 1])]);

final k1 = course([0, 0, 0, 1000]);
final k3 = course([0, 0, 0, 1000, 0, 0]);
final k4 = course([0, 0, 500, 0, 500, 500, 0, 500, 0, 0]);
final k5 = course([0, 0, 300, 300, 300, 0, 0, 300]);

/// 평면 위를 움직이며 입력을 만든다. 기본 2초에 5m, 정확도 5m
class Walk {
  Walk() {
    event(RunKind.start);
  }
  final inputs = <RunInput>[];
  int ms = 0;
  double x = 0, y = 0;

  Walk walk(double toX, double toY, [double step = 5, int stepMs = 2000]) {
    final n = (math.sqrt(math.pow(toX - x, 2) + math.pow(toY - y, 2)) / step).ceil();
    final fromX = x, fromY = y;
    for (var i = 1; i <= n; i++) {
      x = fromX + (toX - fromX) * i / n;
      y = fromY + (toY - fromY) * i / n;
      ms += stepMs;
      gps();
    }
    return this;
  }

  Walk at(double atX, double atY) {
    x = atX;
    y = atY;
    ms += 2000;
    return gps();
  }

  Walk stay(int seconds) {
    for (var i = 0; i < seconds ~/ 2; i++) {
      ms += 2000;
      gps();
    }
    return this;
  }

  Walk gps([double accuracyM = 5]) {
    final p = geo(x, y);
    inputs.add(RunInput(
      seq: inputs.length,
      kind: RunKind.gps,
      elapsedMs: ms,
      measuredAt: DateTime.utc(2026, 10, 15).add(Duration(milliseconds: ms)),
      lat: p.lat,
      lng: p.lng,
      accuracyM: accuracyM,
    ));
    return this;
  }

  Walk event(RunKind kind) {
    inputs.add(RunInput(
      seq: inputs.length,
      kind: kind,
      elapsedMs: ms,
      measuredAt: DateTime.utc(2026, 10, 15).add(Duration(milliseconds: ms)),
    ));
    return this;
  }
}

CourseTracker track(RouteGeometry route, Walk walk) => CourseTracker(route)..feed(walk.inputs);

List<double> placed(CourseTracker tracker) => tracker.points.map((p) => p.s).nonNulls.toList();

TrackPoint near(CourseTracker tracker, double s) =>
    tracker.points.firstWhere((p) => p.s != null && (p.s! - s).abs() < .5);

Matcher sorted() => predicate<List<double>>((values) {
  for (var i = 1; i < values.length; i++) {
    if (values[i] < values[i - 1]) return false;
  }
  return true;
}, 'sorted');

void main() {
  test('course lengths match the expected courses', () {
    expect(k1.length, closeTo(1000, 1e-6));
    expect(k3.length, closeTo(2000, 1e-6));
    expect(k4.length, closeTo(2000, 1e-6));
    expect(k5.length, closeTo(1148.5, .1));
  });

  test('straight route is tracked and connected', () {
    final t = track(k1, Walk().at(0, 0).walk(0, 1000));

    expect(t.points.every((p) => p.s != null), true);
    expect(t.points.first.connected, false);
    expect(t.points.skip(1).every((p) => p.connected), true);
    expect(t.positionM, closeTo(1000, 1e-6));
    expect(t.recognizedM, closeTo(1000, 1e-6));
  });

  test('loop start is held then resolved to zero', () {
    final t = track(k4, Walk().at(0, 0).walk(500, 0));

    expect(t.points.first.s, closeTo(0, 1e-6));
    expect(placed(t), allOf(sorted(), hasLength(t.points.length)));
  });

  test('standing at the loop start stays held (S-04)', () {
    expect(placed(track(k4, Walk().at(0, 0).stay(60).event(RunKind.end))), isEmpty);
  });

  test('full loop ends at the finish, not the start (S-05)', () {
    final t = track(k4, Walk().at(0, 0).walk(500, 0).walk(500, 500).walk(0, 500).walk(0, 0));

    expect(placed(t), sorted());
    expect(t.positionM, closeTo(2000, 1e-6));
  });

  test('out and back takes the return leg after the turnaround (S-01)', () {
    final t = track(k3, Walk().at(0, 0).walk(0, 1000).walk(0, 0));

    expect(placed(t), allOf(sorted(), hasLength(t.points.length)));
    expect(t.positionM, closeTo(2000, 1e-6));
  });

  test('figure eight crossing does not confuse the legs (S-07)', () {
    final t = track(k5, Walk().at(0, 0).walk(300, 300).walk(300, 0).walk(0, 300));

    expect(placed(t), allOf(sorted(), hasLength(t.points.length)));
    expect(t.positionM, closeTo(k5.length, 1e-6));
  });

  test('crossing after a gap is held until the direction is known (S-08)', () {
    final t = track(k5, Walk().at(0, 0).walk(100, 100).event(RunKind.gap).at(150, 150).walk(250, 250));

    expect(near(t, 212.13).connected, false);
    expect(placed(t), allOf(sorted(), hasLength(t.points.length)));
  });

  test('movement while paused is ignored and the resume is not bridged (R-03)', () {
    final t = track(
      k1,
      Walk().at(0, 0).walk(0, 300).event(RunKind.pause).walk(0, 500).event(RunKind.resume).walk(0, 600),
    );

    expect(placed(t).where((s) => s > 300 && s < 500), isEmpty);
    expect(near(t, 505).connected, false);
    expect(near(t, 510).connected, true);
  });

  test('more than ten seconds without GPS breaks the connection', () {
    final walk = Walk().at(0, 0).walk(0, 100);
    walk
      ..ms += 10001
      ..y = 200
      ..gps()
      ..walk(0, 205);

    final t = track(k1, walk);
    expect(near(t, 200).connected, false);
    expect(t.recognizedM, closeTo(105, 1e-6));
  });

  test('inputs after SEGMENT_END are dropped', () {
    final t = track(k1, Walk().at(0, 0).walk(0, 500).event(RunKind.segmentEnd).walk(0, 1000));

    expect(t.positionM, closeTo(500, 1e-6));
  });

  test('a GPS jump over the speed limit breaks only that step', () {
    final t = track(
      k1,
      Walk().at(0, 0).walk(0, 100).walk(0, 95, 5, 1000).walk(0, 111, 16, 1000).walk(0, 114, 3, 1000),
    );

    expect(near(t, 111).connected, false);
    expect(t.points.last.connected, true);
    expect(t.recognizedM, closeTo(103, 1e-6)); // [0, 100] + [111, 114]
  });

  test('a jump along the route is not connected', () {
    final t = track(k1, Walk().at(0, 0).walk(0, 100).at(0, 400).walk(0, 450));

    expect(near(t, 400).connected, false);
    expect(near(t, 405).connected, true);
  });

  test('feeding new inputs bit by bit gives the same result as all at once', () {
    final walk = Walk().at(0, 0).walk(500, 0).walk(500, 500).walk(0, 500).walk(0, 0);
    final live = CourseTracker(k4);
    for (var n = 1; n <= walk.inputs.length; n += 7) {
      live.feed(walk.inputs.sublist(0, n));
    }
    live.feed(walk.inputs);

    final batch = track(k4, walk);
    expect(live.points.map((p) => (p.s, p.connected)), batch.points.map((p) => (p.s, p.connected)));
    expect(live.recognizedM, closeTo(batch.recognizedM, 1e-9));
  });

  test('kilometre markers sit on the route every 1 km from the start', () {
    final markers = k3.kilometres();

    expect(markers.map((m) => m.$1), [1, 2]);
    expect(markers[0].$2.distanceTo(geo(0, 1000)), lessThan(.01));
    expect(markers[1].$2.distanceTo(geo(0, 0)), lessThan(.01)); // 돌아온 출발점이 2 km
  });

  test('course guidance shows progress, remaining distance and the next kilometre', () {
    final guide = CourseLive('왕복 코스', track(k3, Walk().at(0, 0).walk(0, 500)));

    expect(guide.progress, closeTo(.25, 1e-6));
    expect(guide.remainingM, closeTo(1500, 1e-6));
    expect(guide.nextTarget, '1 km 지점까지 500 m');

    final finishing = CourseLive('왕복 코스', track(k3, Walk().at(0, 0).walk(0, 1000).walk(0, 300)));
    expect(finishing.nextTarget, '도착까지 300 m');
  });

  testWidgets('course run screen shows the course, its kilometres and the progress', (tester) async {
    final guide = CourseLive('왕복 코스', track(k3, Walk().at(0, 0).walk(0, 500)));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
        child: MaterialApp(
          home: FreeRunLiveView(
            run: live.RunSnapshot(
              state: live.RunState.running,
              sessionId: 'run-1',
              startedAt: DateTime.utc(2026, 10, 21),
              elapsed: const Duration(minutes: 4),
              active: const Duration(minutes: 4),
              distanceMeters: 500,
              inputs: const [],
              segments: [
                [live.RunPoint(geo(0, 0).lat, geo(0, 0).lng), live.RunPoint(geo(0, 500).lat, geo(0, 500).lng)],
              ],
            ),
            course: guide,
            onPause: () {},
            onResume: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(find.text('왕복 코스'), findsOneWidget);
    expect(find.text('코스 진행'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('1 km 지점까지 500 m'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(700, 0)); // 왼쪽 지도
    await tester.pumpAndSettle();
    expect(find.text('1 km'), findsOneWidget);
    expect(find.text('2 km'), findsOneWidget);
    expect(find.text('남은 거리 1.50 km'), findsOneWidget);
  });
}
