import 'dart:math' as math;

import 'motion_pace.dart';
import 'run_lap.dart';
import 'run_cadence.dart';
import 'run_result_stats.dart';

enum RunPhase { running, paused, ended }

enum RunKind {
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
    this.steps,
    this.durationMs,
    this.sampleEndMs,
    this.altitudeM,
    this.altitudeAccuracyM,
    this.pressureHpa,
    this.pressureAccuracy,
  });
  factory RunInput.fromJson(Map<String, dynamic> j) => RunInput(
    seq: j['seq'] as int,
    kind: j['kind'] == 'SEGMENT_END'
        ? RunKind.segmentEnd
        : RunKind.values.byName((j['kind'] as String).toLowerCase()),
    elapsedMs: j['elapsedMs'] as int,
    measuredAt: DateTime.parse(j['measuredAt'] as String),
    lat: (j['location']?['lat'] as num?)?.toDouble(),
    lng: (j['location']?['lng'] as num?)?.toDouble(),
    accuracyM: (j['accuracyM'] as num?)?.toDouble(),
    reason: j['reason'] as String?,
    speedMps: (j['speedMps'] as num?)?.toDouble(),
    speedAccuracyMps: (j['speedAccuracyMps'] as num?)?.toDouble(),
    steps: (j['steps'] as num?)?.toInt(),
    durationMs: (j['durationMs'] as num?)?.toInt(),
    sampleEndMs: (j['sampleEndMs'] as num?)?.toInt(),
    altitudeM: (j['altitudeM'] as num?)?.toDouble(),
    altitudeAccuracyM: (j['altitudeAccuracyM'] as num?)?.toDouble(),
    pressureHpa: (j['pressureHpa'] as num?)?.toDouble(),
    pressureAccuracy: (j['pressureAccuracy'] as num?)?.toInt(),
  );
  final int seq, elapsedMs;
  final int? steps, durationMs, sampleEndMs;
  final RunKind kind;
  final DateTime measuredAt;
  final double? lat, lng, accuracyM;
  final String? reason;
  final double? speedMps, speedAccuracyMps;

  /// Optional raw vertical measurements in metres; never used for horizontal pace.
  final double? altitudeM, altitudeAccuracyM;

  /// Raw hPa and Android accuracy status (0..3); status is not an error in metres.
  final double? pressureHpa;
  final int? pressureAccuracy;
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
    'kind': kind == RunKind.segmentEnd
        ? 'SEGMENT_END'
        : kind.name.toUpperCase(),
    'elapsedMs': elapsedMs,
    'measuredAt': measuredAt.toUtc().toIso8601String(),
    if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
    if (accuracyM != null) 'accuracyM': accuracyM,
    if (reason != null) 'reason': reason,
    if (speedMps != null) 'speedMps': speedMps,
    if (speedAccuracyMps != null) 'speedAccuracyMps': speedAccuracyMps,
    if (steps != null) 'steps': steps,
    if (durationMs != null) 'durationMs': durationMs,
    if (sampleEndMs != null) 'sampleEndMs': sampleEndMs,
    if (altitudeM != null) 'altitudeM': altitudeM,
    if (altitudeAccuracyM != null) 'altitudeAccuracyM': altitudeAccuracyM,
    if (pressureHpa != null) 'pressureHpa': pressureHpa,
    if (pressureAccuracy != null) 'pressureAccuracy': pressureAccuracy,
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
    this.summary,
    this.inputsLoaded = true,
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
  Map<String, dynamic>? result, summary;
  final bool inputsLoaded;
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
    this.averageCadence,
    this.currentCadence,
    this.cadenceCoverageMs = 0,
    this.steps = 0,
  }) : movingMs = movingMs ?? activeMs;
  final double distanceM;
  final int elapsedMs, activeMs, gapCount;
  final int movingMs;
  final double? currentPaceSecondsPerKm;
  final bool stationary;
  final double? averageCadence, currentCadence;
  final int cadenceCoverageMs, steps;
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
    'averageCadence': averageCadence,
    'cadenceCoverageMs': cadenceCoverageMs,
    'steps': steps,
  };
}

/// Incremental calculation shared by live display, recovery and fixture replay.
class RunCalculator {
  RunResultStats? _resultStats;
  RunResultStats resultStats(List<RunInput> inputs) {
    if (!ended) {
      return RunResultStats.calculate(inputs, segments, lapsAt(lastMs));
    }
    if (_resultStats?.version != RunResultStats.currentVersion) {
      _resultStats = RunResultStats.calculate(inputs, segments, lapsAt(lastMs));
    }
    return _resultStats!;
  }

  double _distanceM = 0;
  final MotionPace _motion = MotionPace();
  bool _v2 = false;
  double get distanceM => _v2 ? _motion.distanceM : _distanceM;
  int activeMs = 0, lastMs = 0, gapCount = 0;
  bool paused = false, ended = false, _inGap = false;
  RunInput? _previous;
  final RunCadenceCalculator _cadence = RunCadenceCalculator();
  final List<RunTimeSpan> _pauses = [];
  int? _pauseAt;
  final List<RunTravel> _travels = [];
  final List<RunLap> _laps = [];
  int _processedTravels = 0, _lapEndMs = 0, _lapMovingMs = 0;
  double _lapDistance = 0;
  int movingAt(int ms) {
    final stopped = _v2 ? _motion.stoppedBefore(ms) : 0;
    var pause = _pauses.fold<int>(0, (sum, p) => sum + p.before(ms));
    if (_pauseAt != null) pause += math.max(0, ms - _pauseAt!);
    return (ms - pause - stopped).clamp(0, ms);
  }

  void _updateLaps() {
    final travels = _v2 ? _motion.travels : _travels;
    for (; _processedTravels < travels.length; _processedTravels++) {
      final t = travels[_processedTravels];
      var boundary = (_laps.length + 1) * 1000.0;
      while (t.distanceM > 0 &&
          boundary <= _lapDistance + t.distanceM + .000001) {
        final fraction = ((boundary - _lapDistance) / t.distanceM).clamp(
          0.0,
          1.0,
        );
        final ms = (t.startMs + (t.endMs - t.startMs) * fraction).round();
        final moving = movingAt(ms);
        _laps.add(
          RunLap(
            number: _laps.length + 1,
            distanceM: 1000,
            movingMs: math.max(0, moving - _lapMovingMs),
            elapsedMs: ms - _lapEndMs,
            complete: true,
          ),
        );
        _lapEndMs = ms;
        _lapMovingMs = moving;
        boundary += 1000;
      }
      _lapDistance += t.distanceM;
    }
  }

  List<RunLap> lapsAt(int ms) {
    final partial = distanceM - _laps.length * 1000;
    return List.unmodifiable([
      ..._laps,
      if (partial > .000001)
        RunLap(
          number: _laps.length + 1,
          distanceM: partial,
          movingMs: math.max(0, movingAt(ms) - _lapMovingMs),
          elapsedMs: math.max(0, ms - _lapEndMs),
          complete: false,
        ),
    ]);
  }

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
      case RunKind.segmentEnd:
      case RunKind.barometer:
        break;
      case RunKind.cadence:
        if (!paused &&
            input.steps != null &&
            input.durationMs != null &&
            (input.sampleEndMs ?? input.elapsedMs) <= input.elapsedMs &&
            (input.sampleEndMs ?? input.elapsedMs) - input.durationMs! >=
                (_pauses.lastOrNull?.end ?? 0)) {
          _cadence.add(
            input.sampleEndMs ?? input.elapsedMs,
            input.steps!,
            input.durationMs!,
          );
        }
        break;
      case RunKind.pause:
        paused = true;
        _pauseAt = input.elapsedMs;
        _break();
      case RunKind.resume:
        paused = false;
        if (_pauseAt != null) {
          _pauses.add(RunTimeSpan(_pauseAt!, input.elapsedMs));
        }
        _pauseAt = null;
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
            _travels.add(RunTravel(previous.elapsedMs, input.elapsedMs, d));
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
    _updateLaps();
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
      averageCadence: _cadence.average,
      currentCadence: !paused && !ended ? _cadence.current(ms) : null,
      cadenceCoverageMs: _cadence.coverageMs,
      steps: _cadence.steps,
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
