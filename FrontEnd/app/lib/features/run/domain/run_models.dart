import 'dart:math' as math;

import 'course_run.dart';
import 'run_lap.dart';
import 'run_result_stats.dart';

enum RunState { ready, running, paused, finished }

enum RunInputKind {
  start,
  gps,
  pause,
  resume,
  gap,
  segmentEnd,
  end,
  cadence,
  barometer,
}

class RunPoint {
  const RunPoint(this.latitude, this.longitude);
  final double latitude, longitude;

  double distanceTo(RunPoint other) {
    final lat = (other.latitude - latitude) * math.pi / 180;
    final lng = (other.longitude - longitude) * math.pi / 180;
    final a =
        math.pow(math.sin(lat / 2), 2) +
        math.cos(latitude * math.pi / 180) *
            math.cos(other.latitude * math.pi / 180) *
            math.pow(math.sin(lng / 2), 2);
    return 6371008.8 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}

/// GPS, sensor and button actions share the recording stream's sequence.
class RunInput {
  const RunInput({
    required this.seq,
    required this.kind,
    required this.elapsedMs,
    required this.measuredAt,
    this.point,
    this.accuracyM,
  });
  final int seq, elapsedMs;
  final RunInputKind kind;
  final DateTime measuredAt;
  final RunPoint? point;
  final double? accuracyM;

  Map<String, Object?> toJson() => {
    'seq': seq,
    'kind': kind == RunInputKind.segmentEnd
        ? 'SEGMENT_END'
        : kind.name.toUpperCase(),
    'elapsedMs': elapsedMs,
    'measuredAt': measuredAt.toUtc().toIso8601String(),
    'location': point == null
        ? null
        : {'lat': point!.latitude, 'lng': point!.longitude},
    'accuracyM': accuracyM,
  };
}

class RunSnapshot {
  RunSnapshot({
    required this.state,
    required this.sessionId,
    required this.startedAt,
    required this.elapsed,
    required this.active,
    required this.distanceMeters,
    required List<RunInput> inputs,
    this.gpsStatus = 'GPS 수집 준비',
    this.storageStatus = '저장 전',
    this.notice,
    this.endReason,
    this.gapCount = 0,
    this.segments = const [],
    this.moving,
    this.averagePaceDisplay,
    this.currentPaceDisplay,
    this.paceDisplayManaged = false,
    this.stationary = false,
    this.laps = const [],
    this.averageCadence,
    this.currentCadence,
    this.cadenceCoverageMs = 0,
    this.cadenceStatus = '측정 전',
    this.voiceNotice,
    this.resultStats,
    this.liveElevationGainM,
    this.course,
    this.gpsGapPassed,
  }) : inputs = List.unmodifiable(inputs);

  /// 서버 코스 판정. 코스 러닝 기록을 서버가 처리한 뒤에만 있다
  final RunCourseResult? course;

  /// 서버의 GPS 코스 등록 끊긴 구간 판단(`gpsGap.passed`). 판단 전·업로드 전이면 null
  final bool? gpsGapPassed;

  final RunState state;
  final String? sessionId;
  final DateTime? startedAt;
  final Duration elapsed, active;
  final double distanceMeters;
  final List<RunInput> inputs;
  final String gpsStatus, storageStatus;
  final String? notice, endReason;
  final int gapCount;
  final Duration? moving;
  Duration get movingTime => moving ?? active;
  final double? averagePaceDisplay, currentPaceDisplay;
  final bool paceDisplayManaged, stationary;
  final List<RunLap> laps;
  final double? averageCadence, currentCadence;
  final int cadenceCoverageMs;
  final String cadenceStatus;
  final String? voiceNotice;
  final RunResultStats? resultStats;
  final double? liveElevationGainM;
  final List<List<RunPoint>> segments;
  bool get hasLocation =>
      segments.any((s) => s.isNotEmpty) ||
      inputs.any(
        (p) =>
            p.kind == RunInputKind.gps &&
            p.point != null &&
            p.accuracyM != null &&
            p.accuracyM!.isFinite &&
            p.accuracyM! >= 0 &&
            p.accuracyM! <= 30,
      );
  // Free running uses moving time; elapsed time remains available for rankings.
  double? get paceSecondsPerKm => paceDisplayManaged
      ? averagePaceDisplay
      : distanceMeters > 0
      ? movingTime.inMilliseconds / distanceMeters
      : null;
  double? get elapsedPaceSecondsPerKm =>
      distanceMeters > 0 ? elapsed.inMilliseconds / distanceMeters : null;
}

String formatRunTime(Duration duration) {
  final seconds = duration.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final tail =
      '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  return hours > 0 ? '${hours.toString().padLeft(2, '0')}:$tail' : tail;
}

String formatRunPace(double? seconds) {
  if (seconds == null) return '—';
  final value = seconds.round();
  return '${value ~/ 60}′${(value % 60).toString().padLeft(2, '0')}″';
}
