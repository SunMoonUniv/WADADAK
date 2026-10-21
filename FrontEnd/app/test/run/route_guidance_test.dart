import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/domain/route_guidance.dart';
import 'package:wadadak/features/run/presentation/course_deviation_alert.dart';

import 'course_tracker_test.dart' show Walk, geo, k1;

/// 이탈·복귀 안내(정책 6·7장). 코스 K1은 (0,0) → (0,1000) 직선이라 x가 곧 경로까지 거리다.
/// 걷기는 기본 2초에 5m. 경로 밖으로는 12m/s 안으로 걸어 나가야 믿을 수 있는 위치다.
class Guided {
  Guided() : guidance = RouteGuidance(k1);
  final RouteGuidance guidance;
  final walk = Walk();
  int _seen = 0;

  /// 입력을 하나씩 넣으며 (입력 시각, 할 일)을 모은다
  final cues = <(int, GuidanceCue)>[];

  Guided run(void Function(Walk walk) steps) {
    steps(walk);
    for (; _seen < walk.inputs.length; _seen++) {
      final input = walk.inputs[_seen];
      for (final cue in guidance.feed(walk.inputs.sublist(0, _seen + 1))) {
        cues.add((input.elapsedMs, cue));
      }
    }
    return this;
  }

  List<GuidanceCue> get kinds => cues.map((c) => c.$2).toList();
  int at(GuidanceCue cue) => cues.firstWhere((c) => c.$2 == cue).$1;
}

void main() {
  test('nearest point and distance to the route', () {
    final nearest = k1.nearest(geo(40, 500).lat, geo(40, 500).lng);

    expect(nearest.d, closeTo(40, 1e-6));
    expect(nearest.point.distanceTo(geo(0, 500)), lessThan(.01));
  });

  test('leaving the route plays the candidate voice once, then alerts after 10 seconds and 3 fixes', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).walk(35, 100)); // x = 35에서 후보
    expect(g.kinds, [GuidanceCue.candidate]);
    expect(g.guidance.state, GuidanceState.candidate);
    final candidateAt = g.at(GuidanceCue.candidate);

    g.run((w) => w.stay(10));
    expect(g.kinds, [GuidanceCue.candidate, GuidanceCue.alert]);
    expect(g.at(GuidanceCue.alert) - candidateAt, 10000);
    expect(g.guidance.state, GuidanceState.off);
    expect(g.guidance.alertOpen, true);
    expect(g.guidance.distanceM, closeTo(35, 1e-6));

    g.run((w) => w.stay(20)); // 열려 있으면 쌓지 않는다
    expect(g.kinds, [GuidanceCue.candidate, GuidanceCue.alert]);
  });

  test('a GPS jump off the route is not trusted and does not even become a candidate', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).at(40, 100).at(0, 100).walk(0, 200));

    expect(g.kinds, isEmpty);
    expect(g.guidance.state, GuidanceState.onRoute);
  });

  test('coming back within 30 m before confirmation cancels the candidate', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).walk(35, 100).walk(25, 100).stay(20));

    expect(g.kinds, [GuidanceCue.candidate]);
    expect(g.guidance.state, GuidanceState.onRoute);
  });

  test('poor GPS holds the decision and restarts the 10 seconds', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).walk(35, 100).stay(6));
    g.run((w) {
      w.ms += 2000;
      w.gps(50); // 정확도 30 m 초과
    });
    final poorAt = g.walk.ms;
    g.run((w) => w.stay(12));

    // 나쁜 표본 다음 표본(+2초)부터 다시 10초
    expect(g.at(GuidanceCue.alert), poorAt + 2000 + 10000);
  });

  test('returning within 20 m for 5 seconds and 3 fixes closes the alert', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).walk(35, 100).stay(10));
    expect(g.guidance.alertOpen, true);

    g.run((w) => w.walk(0, 100).stay(6));
    expect(g.kinds.last, GuidanceCue.dismiss);
    expect(g.guidance.state, GuidanceState.onRoute);
    expect(g.guidance.alertOpen, false);
  });

  test('confirm closes the alert and alerts again 30 seconds later while still off', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).walk(35, 100).stay(10));
    final confirmedAt = g.walk.ms;
    g.guidance.acknowledge(confirmedAt);
    expect(g.guidance.alertOpen, false);

    g.run((w) => w.stay(28));
    expect(g.kinds.where((c) => c == GuidanceCue.alert), hasLength(1));
    g.run((w) => w.stay(2));
    expect(g.cues.last, (confirmedAt + 30000, GuidanceCue.alert));
  });

  test('leaving again within 15 seconds of returning waits for the grace period', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).walk(35, 100).stay(10).walk(0, 100).stay(6));
    final returnedAt = g.at(GuidanceCue.dismiss);
    g.guidance.acknowledge(returnedAt); // 닫힌 뒤라 영향 없다

    g.run((w) => w.walk(40, 100, 20, 2000).stay(10)); // 10 m/s로 나가 후보·확정은 유예 안
    final alerts = g.cues.where((c) => c.$2 == GuidanceCue.alert).map((c) => c.$1).toList();
    expect(alerts, hasLength(2));
    expect(alerts.last, greaterThanOrEqualTo(returnedAt + RouteGuidance.graceMs));
    expect(g.kinds.where((c) => c == GuidanceCue.candidate), hasLength(1)); // 유예 중 후보 음성도 없다
  });

  test('"do not show again" turns off every deviation alert for this run', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).walk(35, 100).stay(10));
    g.guidance.mute();

    g.run((w) => w.walk(0, 100).stay(20).walk(35, 100).stay(40));
    expect(g.kinds, [GuidanceCue.candidate, GuidanceCue.alert]);
    expect(g.guidance.state, GuidanceState.off); // 판단은 계속한다(지도 표시용)
  });

  test('pausing closes the alert and starts over after resuming', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).walk(35, 100).stay(10));
    g.run((w) => w.event(RunKind.pause));

    expect(g.kinds.last, GuidanceCue.dismiss);
    expect(g.guidance.state, GuidanceState.onRoute);
    expect(g.guidance.distanceM, isNull);

    g.run((w) => w.stay(20)); // 정지 중 위치는 보지 않는다
    expect(g.kinds.last, GuidanceCue.dismiss);
    g.run((w) => w.event(RunKind.resume).stay(2));
    expect(g.kinds.last, GuidanceCue.candidate); // 재개 뒤 위치를 다시 확인
  });

  test('no deviation alerts after the course segment ends', () {
    final g = Guided().run((w) => w.at(0, 0).walk(0, 100).event(RunKind.segmentEnd).walk(35, 100).stay(20));

    expect(g.kinds, isEmpty);
  });

  testWidgets('deviation popup shows on alert, reports the choice and closes when the runner returns', (tester) async {
    var confirmed = 0, muted = 0;
    Future<void> show(bool open) async {
      await tester.pumpWidget(MaterialApp(
        home: CourseDeviationAlert(
          open: open,
          onConfirm: () => confirmed++,
          onMute: () => muted++,
          child: const Text('러닝 화면'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await show(true);
    expect(find.text('코스를 벗어났어요'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('코스를 벗어났어요'), findsNothing);
    expect((confirmed, muted), (1, 0));

    await show(false);
    await show(true); // 30초 뒤 다시
    await tester.tap(find.text('다시 표시하지 않음'));
    await tester.pumpAndSettle();
    expect((confirmed, muted), (1, 1));

    await show(false);
    await show(true);
    await show(false); // 복귀하면 버튼 없이 닫는다
    expect(find.text('코스를 벗어났어요'), findsNothing);
    expect(find.text('러닝 화면'), findsOneWidget);
    expect((confirmed, muted), (1, 1));
  });
}
