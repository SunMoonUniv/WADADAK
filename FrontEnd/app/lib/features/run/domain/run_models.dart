import 'dart:math' as math;

enum RunState { ready, running, paused, finished }

enum RunInputKind { start, gps, pause, resume, gap, end }

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

/// GPS and button actions share one sequence, ready for SQLite in the next step.
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
    'kind': kind.name.toUpperCase(),
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
  }) : inputs = List.unmodifiable(inputs);

  final RunState state;
  final String? sessionId;
  final DateTime? startedAt;
  final Duration elapsed, active;
  final double distanceMeters;
  final List<RunInput> inputs;
  bool get hasLocation => inputs.any((p) => p.kind == RunInputKind.gps);
  // Total elapsed time includes pauses, as required by the running policy.
  double? get paceSecondsPerKm =>
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
