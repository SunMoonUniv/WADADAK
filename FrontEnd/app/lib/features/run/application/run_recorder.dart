import 'dart:async';

import '../data/run_local_store.dart';
import '../domain/recording_models.dart';
import '../domain/ghost_run.dart';
import '../../../core/time/monotonic_clock.dart';

class RunStorageFailure implements Exception {
  const RunStorageFailure(this.cause);
  final Object cause;
  @override
  String toString() => '기기 저장을 완료하지 못했어요.';
}

class RunRecorder {
  RunRecorder(
    this.store,
    this.nowMs, {
    this.motionFiltering = true,
    this.recoveryClock,
  });
  final Future<RunClockSample> Function()? recoveryClock;
  final bool motionFiltering;
  final RunStore store;
  final Future<int> Function() nowMs;
  final changes = StreamController<void>.broadcast();
  LocalRun? current;
  RunCalculator calculator = RunCalculator();
  final RunAutoResume _autoResume = RunAutoResume();
  int _originMs = 0;
  int _pressureBoundaryMs = 0, _lastPressureMs = -1;
  int elapsedMs = 0;
  bool confirmingEnd = false;
  bool faulted = false;
  Future<void> _queue = Future.value();
  Future<T> _serial<T>(Future<T> Function() job) {
    final work = _queue.then((_) {
      if (faulted) throw const RunStorageFailure('recording stopped');
      return job();
    });
    _queue = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }

  Future<void> _persist(Future<void> Function() save) async {
    try {
      await save();
    } on Object catch (e) {
      faulted = true;
      elapsedMs = current?.checkpointMs ?? 0;
      changes.add(null);
      throw RunStorageFailure(e);
    }
  }

  RunMetrics get metrics => calculator.at(elapsedMs);
  bool get active => current != null && current!.phase != RunPhase.ended;
  Future<void> start(String id, String owner, DateTime utc, {int? originMs}) =>
      _serial(() async {
        if (active) {
          throw StateError('진행 중인 러닝이 있어요.');
        }
        final now = await nowMs();
        final origin = originMs ?? now;
        if (origin > now || now - origin > 60000) {
          throw StateError('코스 시작 시간을 다시 확인해 주세요.');
        }
        final run = LocalRun(id: id, owner: owner, startedAt: utc.toUtc());
        final start = RunInput(
          seq: 0,
          kind: RunKind.start,
          elapsedMs: 0,
          measuredAt: run.startedAt,
          reason: motionFiltering ? 'PACE_V3' : null,
        );
        await _persist(() => store.create(run, start));
        run.inputs.add(start);
        current = run;
        calculator = RunCalculator()..add(start);
        _originMs = origin;
        _pressureBoundaryMs = 0;
        _lastPressureMs = -1;
        elapsedMs = 0;
        _autoResume.reset();
        if (originMs != null && now > origin) {
          // The request wait counts as elapsed time, with an explicit unmeasured gap.
          await _commit(
            _recoveryGap(run, now - origin),
            RunPhase.running,
            now - origin,
          );
        }
        changes.add(null);
      });
  Future<void> tick({bool persist = false}) => _serial(() async {
    if (!active) return;
    final ms = await _elapsed();
    if (persist) {
      await _saveCheckpoint(current!, ms, () => store.checkpoint(current!, ms));
      current!.checkpointMs = ms;
    }
    elapsedMs = ms;
    changes.add(null);
  });
  Future<int> _elapsed() async =>
      (await nowMs() - _originMs).clamp(elapsedMs, 1 << 52);
  Future<void> gps(
    double lat,
    double lng,
    double accuracyM, {
    DateTime? measuredAt,
    double? speedMps,
    double? speedAccuracyMps,
    double? altitudeM,
    double? altitudeAccuracyM,
  }) => _serial(() async {
    if (!active) return;
    if (!lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180 ||
        !accuracyM.isFinite ||
        accuracyM < 0) {
      final ms = await _elapsed();
      await _commit(
        [_input(RunKind.gap, ms, reason: 'INVALID_FIX')],
        current!.phase,
        ms,
      );
      _autoResume.reset();
      return;
    }
    // An absent or invalid vertical measurement must not discard usable GPS.
    final height = altitudeM != null && altitudeM.isFinite ? altitudeM : null;
    final heightAccuracy =
        height != null &&
            altitudeAccuracyM != null &&
            altitudeAccuracyM.isFinite &&
            altitudeAccuracyM >= 0
        ? altitudeAccuracyM
        : null;
    final ms = await _elapsed();
    var point = _input(
      RunKind.gps,
      ms,
      lat: lat,
      lng: lng,
      accuracyM: accuracyM,
      measuredAt: measuredAt,
      altitudeM: height,
      altitudeAccuracyM: heightAccuracy,
      speedMps: speedMps != null && speedMps.isFinite && speedMps >= 0
          ? speedMps
          : null,
      speedAccuracyMps:
          speedAccuracyMps != null &&
              speedAccuracyMps.isFinite &&
              speedAccuracyMps >= 0
          ? speedAccuracyMps
          : null,
    );
    final run = current!;
    final batch = <RunInput>[];
    var phase = run.phase;
    if (phase == RunPhase.paused && !confirmingEnd && _autoResume.add(point)) {
      batch.add(_input(RunKind.resume, ms, reason: 'MOVEMENT'));
      phase = RunPhase.running;
      _autoResume.reset();
      point = RunInput(
        seq: run.inputs.length + 1,
        kind: RunKind.gps,
        elapsedMs: ms,
        measuredAt: point.measuredAt,
        lat: lat,
        lng: lng,
        accuracyM: accuracyM,
        speedMps: point.speedMps,
        speedAccuracyMps: point.speedAccuracyMps,
        altitudeM: point.altitudeM,
        altitudeAccuracyM: point.altitudeAccuracyM,
      );
    }
    batch.add(point);
    await _commit(batch, phase, ms);
  });
  Future<void> cadence(int steps, int durationMs, {int? sampleEndClockMs}) =>
      _serial(() async {
        if (!active ||
            current!.phase != RunPhase.running ||
            durationMs <= 0 ||
            durationMs > 10000 ||
            steps < 0 ||
            steps * 1000 > durationMs * 5) {
          return;
        }
        final ms = await _elapsed();
        final end = sampleEndClockMs == null
            ? ms
            : sampleEndClockMs - _originMs;
        if (end < durationMs || end > ms) return;
        final input = RunInput(
          seq: current!.inputs.length,
          kind: RunKind.cadence,
          elapsedMs: ms,
          measuredAt: current!.startedAt.add(Duration(milliseconds: ms)),
          steps: steps,
          durationMs: durationMs,
          sampleEndMs: end,
        );
        await _commit([input], current!.phase, ms);
      });
  Future<void> barometer(
    double pressureHpa,
    int pressureAccuracy, {
    required int sampleClockMs,
  }) => _serial(() async {
    if (!active ||
        current!.phase != RunPhase.running ||
        !pressureHpa.isFinite ||
        pressureHpa <= 0 ||
        pressureAccuracy < 0 ||
        pressureAccuracy > 3) {
      return;
    }
    final ms = await _elapsed();
    final sampleMs = sampleClockMs - _originMs;
    if (sampleMs < _pressureBoundaryMs ||
        sampleMs <= _lastPressureMs ||
        sampleMs > ms ||
        ms - sampleMs > 2000) {
      return;
    }
    final input = RunInput(
      seq: current!.inputs.length,
      kind: RunKind.barometer,
      elapsedMs: ms,
      measuredAt: current!.startedAt.add(Duration(milliseconds: ms)),
      sampleEndMs: sampleMs,
      pressureHpa: pressureHpa,
      pressureAccuracy: pressureAccuracy,
    );
    await _commit([input], current!.phase, ms);
    _lastPressureMs = sampleMs;
  });

  Future<void> pause() => _serial(() async {
    if (!active || current!.phase != RunPhase.running) return;
    final ms = await _elapsed();
    await _commit([_input(RunKind.pause, ms)], RunPhase.paused, ms);
    _autoResume.reset();
  });
  Future<void> resume() => _serial(() async {
    if (!active || current!.phase != RunPhase.paused) return;
    final ms = await _elapsed();
    await _commit(
      [_input(RunKind.resume, ms, reason: 'MANUAL')],
      RunPhase.running,
      ms,
    );
    _autoResume.reset();
  });
  Future<void> gap(String reason) => _serial(() async {
    if (!active) return;
    final ms = await _elapsed();
    await _commit(
      [_input(RunKind.gap, ms, reason: reason)],
      current!.phase,
      ms,
    );
    _autoResume.reset();
  });

  /// 코스 구간 종료(F6). 서버는 이 입력 전까지로 코스를 판정한다. 세션은 같은 상태로 계속된다
  Future<void> segmentEnd(String reason) => _serial(() async {
    if (!active) return;
    final ms = await _elapsed();
    await _commit(
      [_input(RunKind.segmentEnd, ms, reason: reason)],
      current!.phase,
      ms,
    );
  });
  Future<void> end({String reason = 'USER'}) => _serial(() async {
    if (!active) return;
    if (reason == 'USER' && current!.phase != RunPhase.paused) {
      throw StateError('일시정지 후 종료해 주세요.');
    }
    final ms = await _elapsed();
    await _commit(
      [_input(RunKind.end, ms, reason: reason)],
      RunPhase.ended,
      ms,
      pending: calculator.distanceM > 0 || current!.ghost != null,
      reason: reason,
    );
    confirmingEnd = false;
  });
  Future<List<LocalRun>> recover(String owner, {bool summaryOnly = false}) =>
      _serial(() async {
        if (active) {
          if (current!.owner != owner) throw StateError('다른 계정의 러닝이 진행 중이에요.');
          return store.list(owner, summaryOnly: summaryOnly);
        }
        late List<LocalRun> runs;
        await _persist(() async {
          runs = await store.list(owner, unfinishedOnly: summaryOnly);
        });
        for (final run in runs.where((r) => r.phase != RunPhase.ended)) {
          final reading = run.ghost == null ? null : await _readRecoveryClock();
          final anchor = run.recoveryAnchor;
          final since = anchor == null || reading == null
              ? null
              : reading.since(
                  RunClockSample(anchor.checkpointClockMs, anchor.bootId),
                );
          if (run.ghost != null &&
              anchor != null &&
              since != null &&
              since <= 60000 &&
              anchor.originMs == run.ghost!.intent.clock.elapsedMs &&
              anchor.bootId == run.ghost!.intent.clock.bootId &&
              anchor.checkpointClockMs == anchor.originMs + run.checkpointMs &&
              run.ghost!.intent.id == run.id &&
              run.ghost!.intent.owner == run.owner &&
              run.ghost!.intent.startedAt == run.startedAt) {
            current = run;
            calculator = RunCalculator.replay(run.inputs);
            _originMs = anchor.originMs;
            elapsedMs = run.checkpointMs;
            _autoResume.reset();
            confirmingEnd = false;
            final ms = reading!.elapsedMs - _originMs;
            await _commit(_recoveryGap(run, ms), run.phase, ms);
            _pressureBoundaryMs = ms;
            _lastPressureMs = -1;
            continue;
          }
          final ms = run.checkpointMs;
          final calc = RunCalculator.replay(run.inputs);
          final end = RunInput(
            seq: run.inputs.length,
            kind: RunKind.end,
            elapsedMs: ms,
            measuredAt: run.startedAt.add(Duration(milliseconds: ms)),
            reason: 'INTERRUPTED',
          );
          await _persist(
            () => store.append(
              run,
              [end],
              RunPhase.ended,
              ms,
              pending: calc.distanceM > 0 || run.ghost != null,
              endReason: 'INTERRUPTED',
            ),
          );
          run.inputs.add(end);
          run.phase = RunPhase.ended;
          run.endReason = 'INTERRUPTED';
          run.pending = calc.distanceM > 0 || run.ghost != null;
        }
        return summaryOnly ? store.list(owner, summaryOnly: true) : runs;
      });
  RunInput _input(
    RunKind kind,
    int ms, {
    double? lat,
    double? lng,
    double? accuracyM,
    String? reason,
    DateTime? measuredAt,
    double? speedMps,
    double? speedAccuracyMps,
    double? altitudeM,
    double? altitudeAccuracyM,
  }) => RunInput(
    seq: current!.inputs.length,
    kind: kind,
    elapsedMs: ms,
    measuredAt:
        measuredAt?.toUtc() ??
        current!.startedAt.add(Duration(milliseconds: ms)),
    lat: lat,
    lng: lng,
    accuracyM: accuracyM,
    reason: reason,
    speedMps: speedMps,
    speedAccuracyMps: speedAccuracyMps,
    altitudeM: altitudeM,
    altitudeAccuracyM: altitudeAccuracyM,
  );
  Future<void> _commit(
    List<RunInput> batch,
    RunPhase phase,
    int ms, {
    bool pending = false,
    String? reason,
  }) async {
    final run = current!;
    await _saveCheckpoint(
      run,
      ms,
      () => store.append(
        run,
        batch,
        phase,
        ms,
        pending: pending,
        endReason: reason,
      ),
    );
    run.inputs.addAll(batch);
    run.phase = phase;
    run.checkpointMs = ms;
    run.pending = pending;
    run.endReason = reason;
    for (final input in batch) {
      if (input.kind == RunKind.pause ||
          input.kind == RunKind.resume ||
          input.kind == RunKind.gap) {
        _pressureBoundaryMs = input.elapsedMs;
      }
      calculator.add(input);
    }
    elapsedMs = ms;
    changes.add(null);
  }

  Future<RunClockSample?> _readRecoveryClock() async {
    try {
      return await recoveryClock?.call();
    } on Object {
      return null;
    }
  }

  Future<void> _saveCheckpoint(
    LocalRun run,
    int ms,
    Future<void> Function() write,
  ) async {
    final before = run.recoveryAnchor;
    run.recoveryAnchor = before?.at(ms);
    try {
      await _persist(write);
    } on Object {
      run.recoveryAnchor = before;
      rethrow;
    }
  }

  List<RunInput> _recoveryGap(LocalRun run, int ms) => [
    RunInput(
      seq: run.inputs.length,
      kind: RunKind.gap,
      elapsedMs: run.checkpointMs,
      measuredAt: run.startedAt.add(Duration(milliseconds: run.checkpointMs)),
      reason: 'PROCESS_RECOVERY',
    ),
    if (ms > run.checkpointMs)
      RunInput(
        seq: run.inputs.length + 1,
        kind: RunKind.gap,
        elapsedMs: ms,
        measuredAt: run.startedAt.add(Duration(milliseconds: ms)),
        reason: 'PROCESS_RECOVERY',
      ),
  ];

  /// Receipt and START move from the pending ledger into one session transaction.
  Future<bool> startGhost(
    GhostRunContext context, {
    bool recovering = false,
    RunClockSample? checkpointClock,
  }) => _serial(() async {
    if (active) throw StateError('진행 중인 러닝이 있어요.');
    final intent = context.intent;
    final reading = await _readRecoveryClock();
    final saved = checkpointClock ?? intent.clock;
    final since = reading?.since(saved);
    final liveElapsed = reading == null
        ? null
        : reading.elapsedMs - intent.clock.elapsedMs;
    final canContinue =
        since != null &&
            since <= 60000 &&
            reading!.bootId == intent.clock.bootId &&
            saved.elapsedMs >= intent.clock.elapsedMs ||
        !recovering &&
            reading?.bootId == null &&
            intent.clock.bootId == null &&
            liveElapsed != null &&
            liveElapsed >= 0 &&
            liveElapsed <= 60000;
    final run = LocalRun(
      id: intent.id,
      owner: intent.owner,
      startedAt: intent.startedAt,
      ghost: context,
      recoveryAnchor: intent.clock.bootId == null
          ? null
          : RunRecoveryAnchor(
              intent.clock.bootId!,
              intent.clock.elapsedMs,
              intent.clock.elapsedMs,
            ),
    );
    final start = RunInput(
      seq: 0,
      kind: RunKind.start,
      elapsedMs: 0,
      measuredAt: run.startedAt,
      reason: motionFiltering ? 'PACE_V3' : null,
    );
    await _persist(() => store.create(run, start));
    run.inputs.add(start);
    current = run;
    calculator = RunCalculator()..add(start);
    elapsedMs = 0;
    _originMs = intent.clock.elapsedMs;
    _pressureBoundaryMs = 0;
    _lastPressureMs = -1;
    _autoResume.reset();
    confirmingEnd = false;
    if (canContinue) {
      final ms = reading!.elapsedMs - _originMs;
      await _commit(_recoveryGap(run, ms), RunPhase.running, ms);
      _pressureBoundaryMs = ms;
      return true;
    }
    await _commit(
      [
        RunInput(
          seq: 1,
          kind: RunKind.end,
          elapsedMs: 0,
          measuredAt: run.startedAt,
          reason: 'INTERRUPTED',
        ),
      ],
      RunPhase.ended,
      0,
      reason: 'INTERRUPTED',
    );
    return false;
  });

  Future<void> close() async {
    await _queue;
    await changes.close();
  }
}
