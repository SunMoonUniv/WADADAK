import 'run_models.dart';

/// The clock is independent of widgets and refresh timers. Tests can advance it instantly.
class FreeRunSession {
  FreeRunSession({required this.monotonicNow, required this.utcNow});
  final Duration Function() monotonicNow;
  final DateTime Function() utcNow;
  RunState _state = RunState.ready;
  String? _id;
  DateTime? _startedAt;
  Duration _start = Duration.zero, _pausedTotal = Duration.zero;
  Duration? _pauseAt, _end;
  final List<RunInput> _inputs = [];
  RunInput? _previousFix;
  double _distance = 0;

  RunSnapshot get snapshot {
    final tick = _end ?? monotonicNow();
    final elapsed = _state == RunState.ready ? Duration.zero : tick - _start;
    final currentPause = _pauseAt == null ? Duration.zero : tick - _pauseAt!;
    return RunSnapshot(
      state: _state,
      sessionId: _id,
      startedAt: _startedAt,
      elapsed: elapsed,
      active: elapsed - _pausedTotal - currentPause,
      distanceMeters: _distance,
      inputs: _inputs,
    );
  }

  void start(String sessionId) {
    _require(RunState.ready);
    _id = sessionId;
    _startedAt = utcNow().toUtc();
    _start = monotonicNow();
    _state = RunState.running;
    _append(RunInputKind.start, tick: _start);
  }

  void pause() {
    _require(RunState.running);
    _pauseAt = monotonicNow();
    _state = RunState.paused;
    _previousFix = null;
    _append(RunInputKind.pause, tick: _pauseAt);
  }

  void resume() {
    _require(RunState.paused);
    final tick = monotonicNow();
    _pausedTotal += tick - _pauseAt!;
    _pauseAt = null;
    _state = RunState.running;
    _previousFix = null;
    _append(RunInputKind.resume, tick: tick);
  }

  void finish() {
    _require(RunState.paused);
    _end = monotonicNow();
    _state = RunState.finished;
    _append(RunInputKind.end);
  }

  /// Used by synthetic tests now; the location adapter will call this later.
  void addLocation(RunPoint point, {required double accuracyM}) {
    if (_state != RunState.running && _state != RunState.paused) {
      throw StateError('측정 중인 러닝이 없습니다.');
    }
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180 ||
        !accuracyM.isFinite ||
        accuracyM < 0) {
      throw ArgumentError('Invalid location sample');
    }
    final fix = _append(RunInputKind.gps, point: point, accuracyM: accuracyM);
    if (_state == RunState.paused || accuracyM > 30) {
      _previousFix = null;
      return;
    }
    final previous = _previousFix;
    if (previous != null) {
      final ms = fix.elapsedMs - previous.elapsedMs;
      final meters = previous.point!.distanceTo(point);
      // Development quality settings: never bridge gaps, bad fixes, or implausible jumps.
      if (ms > 0 && ms <= 15000 && meters <= ms / 1000 * 12) {
        _distance += meters;
      }
    }
    _previousFix = fix;
  }

  void addGap() {
    if (_state != RunState.running && _state != RunState.paused) {
      throw StateError('측정 중인 러닝이 없습니다.');
    }
    _previousFix = null;
    _append(RunInputKind.gap);
  }

  RunInput _append(
    RunInputKind kind, {
    Duration? tick,
    RunPoint? point,
    double? accuracyM,
  }) {
    final elapsed = (tick ?? _end ?? monotonicNow()) - _start;
    final input = RunInput(
      seq: _inputs.length,
      kind: kind,
      elapsedMs: elapsed.inMilliseconds,
      measuredAt: _startedAt!.add(elapsed),
      point: point,
      accuracyM: accuracyM,
    );
    _inputs.add(input);
    return input;
  }

  void _require(RunState expected) {
    if (_state != expected) throw StateError('이 상태에서는 실행할 수 없습니다: $_state');
  }
}
