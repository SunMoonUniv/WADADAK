import 'dart:math' as math;

import 'motion_pace.dart';

enum RunPhase { running, paused, ended }

enum RunKind { start, gps, pause, resume, gap, end }

class RunInput {
  const RunInput({
    required this.seq,
    required this.kind,
    required this.elapsedMs,
    required this.measuredAt,
    this.lat,
    this.lng,
    this.accuracyM,
    this.reason,
    this.speedMps,
    this.speedAccuracyMps,
  });
  factory RunInput.fromJson(Map<String, dynamic> j) => RunInput(
    seq: j['seq'] as int,
    kind: RunKind.values.byName((j['kind'] as String).toLowerCase()),
    elapsedMs: j['elapsedMs'] as int,
    measuredAt: DateTime.parse(j['measuredAt'] as String),
    lat: (j['location']?['lat'] as num?)?.toDouble(),
    lng: (j['location']?['lng'] as num?)?.toDouble(),
    accuracyM: (j['accuracyM'] as num?)?.toDouble(),
    reason: j['reason'] as String?,
    speedMps: (j['speedMps'] as num?)?.toDouble(),
    speedAccuracyMps: (j['speedAccuracyMps'] as num?)?.toDouble(),
  );
  final int seq, elapsedMs;
  final RunKind kind;
  final DateTime measuredAt;
  final double? lat, lng, accuracyM;
  final String? reason;
  final double? speedMps, speedAccuracyMps;
  bool get good =>
      kind == RunKind.gps &&
      lat != null &&
      lng != null &&
      lat!.isFinite &&
      lng!.isFinite &&
      lat!.abs() <= 90 &&
      lng!.abs() <= 180 &&
      accuracyM != null &&
      accuracyM!.isFinite &&
      accuracyM! >= 0 &&
      accuracyM! <= 30;
  Map<String, dynamic> toJson() => {
    'seq': seq,
    'kind': kind.name.toUpperCase(),
    'elapsedMs': elapsedMs,
    'measuredAt': measuredAt.toUtc().toIso8601String(),
    if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
    if (accuracyM != null) 'accuracyM': accuracyM,
    if (reason != null) 'reason': reason,
    if (speedMps != null) 'speedMps': speedMps,
    if (speedAccuracyMps != null) 'speedAccuracyMps': speedAccuracyMps,
  };
  double distanceTo(RunInput other) {
    const radius = 6371008.8;
    final a = lat! * math.pi / 180, b = other.lat! * math.pi / 180;
    final dLat = b - a, dLng = (other.lng! - lng!) * math.pi / 180;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(a) * math.cos(b) * math.pow(math.sin(dLng / 2), 2);
    return 2 * radius * math.asin(math.sqrt(h.clamp(0, 1)));
  }
}

class LocalRun {
  LocalRun({
    required this.id,
    required this.owner,
    required this.startedAt,
    this.phase = RunPhase.running,
    this.checkpointMs = 0,
    this.pending = false,
    this.endReason,
    this.result,
    this.syncState = 'pending',
    this.syncFailure,
    List<RunInput>? inputs,
  }) : inputs = inputs ?? [];
  final String id, owner;
  final DateTime startedAt;
  RunPhase phase;
  int checkpointMs;
  bool pending;
  String? endReason;
  String syncState;
  String? syncFailure;
  Map<String, dynamic>? result;
  final List<RunInput> inputs;
  DateTime get endedAt => startedAt.add(Duration(milliseconds: checkpointMs));
}

class RunMetrics {
  const RunMetrics(
    this.distanceM,
    this.elapsedMs,
    this.activeMs,
    this.gapCount, {
    int? movingMs,
    this.currentPaceSecondsPerKm,
    this.stationary = false,
  }) : movingMs = movingMs ?? activeMs;
  final double distanceM;
  final int elapsedMs, activeMs, gapCount;
  final int movingMs;
  final double? currentPaceSecondsPerKm;
  final bool stationary;
  double? get paceSecondsPerKm =>
      distanceM > 0 && movingMs > 0 ? movingMs / distanceM : null;
  double? get elapsedPaceSecondsPerKm =>
      distanceM > 0 ? elapsedMs / distanceM : null;
  Map<String, dynamic> toJson() => {
    'distanceM': distanceM,
    'elapsedMs': elapsedMs,
    'activeMs': activeMs,
    'movingMs': movingMs,
    'elapsedPaceSecondsPerKm': elapsedPaceSecondsPerKm,
    'gapCount': gapCount,
    'paceSecondsPerKm': paceSecondsPerKm,
  };
}

/// Incremental calculation shared by live display, recovery and fixture replay.
class RunCalculator {
  double _distanceM = 0;
  final MotionPace _motion = MotionPace();
  bool _v2 = false;
  double get distanceM => _v2 ? _motion.distanceM : _distanceM;
  int activeMs = 0, lastMs = 0, gapCount = 0;
  bool paused = false, ended = false, _inGap = false;
  RunInput? _previous;
  final List<List<RunInput>> _segments = [];
  List<List<RunInput>> get segments => _v2 ? _motion.segments : _segments;
  List<RunInput>? _segment;
  void add(RunInput input) {
    if (ended) return;
    if (input.kind == RunKind.start) _v2 = input.reason == 'PACE_V2';
    if (_v2) _motion.add(input);
    if (!paused) activeMs += input.elapsedMs - lastMs;
    lastMs = input.elapsedMs;
    switch (input.kind) {
      case RunKind.start:
        break;
      case RunKind.pause:
        paused = true;
        _break();
      case RunKind.resume:
        paused = false;
        _break();
      case RunKind.gap:
        if (!paused && !_inGap) gapCount++;
        _inGap = true;
        _break();
      case RunKind.end:
        ended = true;
        _break();
      case RunKind.gps:
        if (paused) {
          _break();
          return;
        }
        if (!input.good) {
          _gap();
          return;
        }
        final previous = _previous;
        if (previous != null) {
          final dt = input.elapsedMs - previous.elapsedMs;
          final d = previous.distanceTo(input);
          if (dt <= 0 || dt > 10000 || d / (dt / 1000) > 12) {
            _gap();
          } else {
            _distanceM += d;
          }
        }
        if (_segment == null) {
          _segment = [];
          _segments.add(_segment!);
        }
        _segment!.add(input);
        _previous = input;
        _inGap = false;
    }
  }

  void _gap() {
    if (!_inGap) gapCount++;
    _inGap = true;
    _break();
  }

  void _break() {
    _previous = null;
    _segment = null;
  }

  RunMetrics at(int ms) {
    final active = activeMs + (!paused && !ended ? ms - lastMs : 0);
    return RunMetrics(
      distanceM,
      ms,
      active,
      gapCount,
      movingMs: _v2 ? _motion.movingMs(ms, active) : active,
      currentPaceSecondsPerKm: _v2 ? _motion.currentPace(ms) : null,
      stationary: _v2 && _motion.stationary,
    );
  }

  static RunCalculator replay(Iterable<RunInput> inputs) {
    final calculator = RunCalculator();
    for (final input in inputs) {
      calculator.add(input);
    }
    return calculator;
  }
}

/// Conservative movement confirmation; poor fixes and stationary jitter reset it.
class RunAutoResume {
  RunInput? _anchor, _previous;
  int _movingIntervals = 0;
  void reset() {
    _anchor = null;
    _previous = null;
    _movingIntervals = 0;
  }

  bool add(RunInput input) {
    if (!input.good || input.accuracyM! > 15) {
      reset();
      return false;
    }
    final previous = _previous;
    _previous = input;
    if (previous == null) {
      _anchor = input;
      return false;
    }
    final dt = input.elapsedMs - previous.elapsedMs;
    final speed = dt > 0 ? previous.distanceTo(input) / (dt / 1000) : 0.0;
    if (dt <= 0 || dt > 10000 || speed < 0.8 || speed > 12) {
      _anchor = input;
      _movingIntervals = 0;
      return false;
    }
    _movingIntervals++;
    return _movingIntervals >= 2 &&
        _anchor!.distanceTo(input) >=
            math.max(8, _anchor!.accuracyM! + input.accuracyM!);
  }
}

String runTime(int ms) {
  final seconds = ms ~/ 1000;
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  return '$m:${(seconds % 60).toString().padLeft(2, '0')}';
}

String runPace(double? seconds) => seconds == null || !seconds.isFinite
    ? '—'
    : '${seconds.floor() ~/ 60}′${(seconds.floor() % 60).toString().padLeft(2, '0')}″ /km';
