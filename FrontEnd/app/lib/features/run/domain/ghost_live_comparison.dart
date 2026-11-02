import '../../../core/map/geo_point.dart';
import 'course_tracker.dart';
import 'recording_models.dart' as recording;

/// Signed values from the existing live replay comparison, never from UI text.
class GhostLiveComparison {
  const GhostLiveComparison({
    this.position,
    this.distanceM,
    this.timeDeltaMs,
    this.ghostProgress,
  });

  final GeoPoint? position;

  /// Positive means the runner is ahead.
  final double? distanceM;

  /// Runner arrival minus ghost arrival at the same course position.
  final double? timeDeltaMs;
  final double? ghostProgress;

  String get distance => distanceM == null
      ? '—'
      : '${distanceM!.abs().round()}m ${distanceM! >= 0 ? '앞서요' : '뒤에 있어요'}';
  String get time => timeDeltaMs == null
      ? '—'
      : '${(timeDeltaMs!.abs() / 1000).round()}초 ${timeDeltaMs! <= 0 ? '앞서요' : '뒤에 있어요'}';

  String get value => distanceM == null
      ? '—'
      : '${distanceM!.round() > 0 ? '+' : ''}${distanceM!.round()} m';
  String get title => distanceM == null
      ? '고스트 위치를 확인하고 있어요'
      : distanceM!.round() == 0
      ? '고스트와 나란히 달리고 있어요'
      : distanceM! > 0
      ? '고스트보다 앞서고 있어요'
      : '고스트를 따라잡고 있어요';
  String get caption => timeDeltaMs == null
      ? '시간차 확인 중'
      : timeDeltaMs!.abs() < 500
      ? '같은 시간에 통과했어요'
      : '약 ${(timeDeltaMs!.abs() / 1000).round()}초 ${timeDeltaMs! < 0 ? '앞서는 중' : '뒤처지는 중'}';
  String get message => distanceM == null
      ? 'GPS가 확인되면 격차를 표시해요.'
      : distanceM! >= 0
      ? '지금 페이스를 이어가세요.'
      : '나만의 페이스로 차근차근 따라가세요.';
}

/// Shared live comparison for screen and audio; never derives time from pace.
GhostLiveComparison compareGhostLive({
  required recording.LocalRun current,
  required CourseTracker tracker,
  required int elapsedMs,
}) {
  tracker.feed(current.inputs);
  final replay = current.ghost!.replay.playback;
  final moment = replay.at(elapsedMs);
  final ghostS = moment.coursePositionM;
  final position = ghostS == null ? null : tracker.route.pointAt(ghostS);
  final last = tracker.points.lastOrNull;
  final boundary = current.inputs
      .where(
        (i) =>
            i.kind == recording.RunKind.gap ||
            i.kind == recording.RunKind.resume,
      )
      .lastOrNull;
  final s = last?.s;
  final fresh =
      last != null &&
      (boundary == null || boundary.seq < last.input.seq) &&
      (current.phase == recording.RunPhase.paused ||
          elapsedMs - last.input.elapsedMs <= 10000);
  if (!fresh || s == null) {
    return GhostLiveComparison(
      position: position,
      ghostProgress: ghostS == null ? null : ghostS / tracker.route.length,
    );
  }
  double? first;
  for (var i = 1; i < tracker.points.length; i++) {
    final a = tracker.points[i - 1], b = tracker.points[i];
    if (b.connected &&
        a.s != null &&
        b.s != null &&
        b.s! > a.s! &&
        s >= a.s! &&
        s <= b.s!) {
      first =
          a.input.elapsedMs +
          (b.input.elapsedMs - a.input.elapsedMs) * (s - a.s!) / (b.s! - a.s!);
      break;
    }
  }
  final opponent = replay.firstArrivalMs(s);
  final reversing =
      tracker.points.length > 1 &&
      tracker.points[tracker.points.length - 2].s != null &&
      s < tracker.points[tracker.points.length - 2].s!;
  final delta = first == null || opponent == null || reversing
      ? null
      : first - opponent;
  return GhostLiveComparison(
    position: position,
    distanceM: ghostS == null ? null : s - ghostS,
    timeDeltaMs: delta,
    ghostProgress: ghostS == null ? null : ghostS / tracker.route.length,
  );
}
