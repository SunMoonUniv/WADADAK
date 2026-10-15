import 'dart:async';

import '../data/run_local_store.dart';
import '../domain/recording_models.dart';

class RunStorageFailure implements Exception {
  const RunStorageFailure(this.cause);
  final Object cause;
  @override
  String toString() => '기기 저장을 완료하지 못했어요.';
}

class RunRecorder {
  RunRecorder(this.store, this.nowMs, {this.motionFiltering = true});
  final bool motionFiltering;
  final RunStore store;
  final Future<int> Function() nowMs;
  final changes = StreamController<void>.broadcast();
  LocalRun? current;
  RunCalculator calculator = RunCalculator();
  final RunAutoResume _autoResume = RunAutoResume();
  int _originMs = 0;
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
  Future<void> start(String id, String owner, DateTime utc) =>
      _serial(() async {
        if (active) {
          throw StateError('진행 중인 러닝이 있어요.');
        }
        final origin = await nowMs();
        final run = LocalRun(id: id, owner: owner, startedAt: utc.toUtc());
        final start = RunInput(
          seq: 0,
          kind: RunKind.start,
          elapsedMs: 0,
          measuredAt: run.startedAt,
          reason: motionFiltering ? 'PACE_V2' : null,
        );
        await _persist(() => store.create(run, start));
        run.inputs.add(start);
        current = run;
        calculator = RunCalculator()..add(start);
        _originMs = origin;
        elapsedMs = 0;
        _autoResume.reset();
        changes.add(null);
      });
  Future<void> tick({bool persist = false}) => _serial(() async {
    if (!active) return;
    final ms = await _elapsed();
    if (persist) {
      await _persist(() => store.checkpoint(current!, ms));
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
    final ms = await _elapsed();
    var point = _input(
      RunKind.gps,
      ms,
      lat: lat,
      lng: lng,
      accuracyM: accuracyM,
      measuredAt: measuredAt,
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
      pending: calculator.distanceM > 0,
      reason: reason,
    );
    confirmingEnd = false;
  });
  Future<List<LocalRun>> recover(String owner, {bool summaryOnly = false}) =>
      _serial(() async {
        late List<LocalRun> runs;
        await _persist(() async {
          runs = await store.list(owner, unfinishedOnly: summaryOnly);
        });
        for (final run in runs.where((r) => r.phase != RunPhase.ended)) {
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
              pending: calc.distanceM > 0,
              endReason: 'INTERRUPTED',
            ),
          );
          run.inputs.add(end);
          run.phase = RunPhase.ended;
          run.endReason = 'INTERRUPTED';
          run.pending = calc.distanceM > 0;
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
  );
  Future<void> _commit(
    List<RunInput> batch,
    RunPhase phase,
    int ms, {
    bool pending = false,
    String? reason,
  }) async {
    final run = current!;
    await _persist(
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
      calculator.add(input);
    }
    elapsedMs = ms;
    changes.add(null);
  }

  Future<void> close() async {
    await _queue;
    await changes.close();
  }
}
