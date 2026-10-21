import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/course_run.dart';
import '../domain/free_run_session.dart';
import '../domain/run_models.dart';
import '../domain/run_result_stats.dart';
import '../domain/recording_models.dart' as recording;
import 'run_controller.dart';
import 'run_result_mapper.dart';

// A regular Provider keeps the session alive when the running tab is hidden.
final freeRunControllerProvider = Provider<FreeRunController>((ref) {
  final controller = FreeRunController.recording(
    ref.watch(runControllerProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

class FreeRunController extends ChangeNotifier {
  FreeRunController({required this.createSession, required this.createId}) {
    _session = createSession!();
  }
  FreeRunController.recording(RunController recorder)
    : createSession = null,
      createId = null,
      _recording = recorder {
    recorder.addListener(notifyListeners);
  }
  final FreeRunSession Function()? createSession;
  final String Function()? createId;
  RunController? _recording;
  RunController? get recordingEngine => _recording;
  late FreeRunSession _session;
  Timer? _countdownTimer, _refreshTimer;
  String? _paceRunId, _paceSignal;
  recording.RunPhase? _pacePhase;
  bool? _paceStationary;
  bool? _paceAvailable;
  int _paceMs = -3000;
  double? _averagePace, _currentPace;
  int? _countdown;
  int? get countdown => _recording?.countdown ?? _countdown;
  bool get preparing => _recording?.preparing ?? (_countdown != null);
  bool get canCancelStart => _recording?.canCancelStart ?? preparing;
  bool get storageFault => _recording?.storageFault ?? false;
  String? get error => _recording?.error;

  /// 코스 상세에서 고른 코스(F6). 있으면 시작이 코스 러닝이 된다
  CourseSelection? get selectedCourse => _recording?.selectedCourse;
  void clearCourse() => _recording?.clearCourse();

  /// 진행 중인 코스 러닝의 안내(C4 코스). 코스 러닝이 아니면 null
  CourseLive? get courseLive {
    final recording = _recording, run = _recording?.run, tracker = _recording?.courseTracker;
    if (recording == null || run == null || tracker == null || !recording.onCourse) return null;
    tracker.feed(run.inputs);
    return CourseLive(recording.course!.name, tracker);
  }

  /// 아직 코스 구간이다. 종료를 고르면 [코스만 종료]도 보인다(RUN-07)
  bool get onCourse => _recording?.onCourse ?? false;

  /// 코스만 종료: 코스 도전을 미완주로 마감하고 같은 세션을 자유 러닝으로 잇는다. 일시정지는 그대로다
  void endCourseOnly() {
    final recording = _recording;
    if (recording != null) unawaited(recording.endCourse('COURSE_ONLY'));
  }

  /// 코스 구간을 끝내고 자유 러닝으로 바뀐 뒤의 안내
  String? get courseNotice => switch (_recording?.courseEndReason) {
    'ROUTE_END' => '코스 끝에 도착했어요. 자유 러닝으로 이어서 기록해요.',
    'COURSE_ONLY' => '코스만 종료했어요. 자유 러닝으로 이어서 기록해요.',
    _ => null,
  };

  /// 코스 러닝 측정 전(RCR-01). 있으면 출발점 안내 지도를 보인다
  CourseStart? get courseStart => _recording?.courseStart;
  void cancelCourseStart() => _recording?.cancelCourseStart();

  /// [run]이 방금 시작한 코스 러닝이면 그 코스. 서버 판정 전 결과 화면에 "판정 대기"로 보인다
  CourseSelection? courseOf(RunSnapshot run) =>
      run.sessionId != null && run.sessionId == _recording?.courseRunId ? _recording?.course : null;
  bool get hasSettingsAction => _recording?.setupAction != null;
  void openSettings() {
    if (_recording != null) unawaited(_recording!.openSettings());
  }

  String get gpsStatus => countdown != null ? '신호 확인 완료' : snapshot.gpsStatus;
  RunSnapshot? get recent => _recording?.records.firstOrNull == null
      ? null
      : savedSnapshot(_recording!.records.first);

  RunSnapshot get snapshot {
    final controller = _recording;
    if (controller == null) return _session.snapshot;
    final run = controller.run;
    if (run == null) {
      return RunSnapshot(
        state: RunState.ready,
        sessionId: null,
        startedAt: null,
        elapsed: Duration.zero,
        active: Duration.zero,
        distanceMeters: 0,
        inputs: const [],
        storageStatus: '시작하면 기기에 기록을 저장해요.',
      );
    }
    return _fromRun(
      run,
      controller.metrics,
      controller.recorder.calculator,
      notice: controller.storageFault ? controller.error : controller.gpsNotice,
    );
  }

  RunSnapshot savedSnapshot(recording.LocalRun run) {
    if (run.result != null) return remoteRunSnapshot(_withLocalStats(run));
    if (!run.inputsLoaded && run.summary != null) {
      return remoteRunSnapshot(
        run.summary!,
        storageStatus: run.syncState == 'synced'
            ? '서버 저장 완료'
            : '기기에 저장됨 · 동기화 대기',
      );
    }
    final calculator = recording.RunCalculator.replay(run.inputs);
    return _fromRun(
      run,
      calculator.at(run.checkpointMs),
      calculator,
      live: false,
    );
  }

  Map<String, dynamic> _withLocalStats(
    recording.LocalRun run, [
    recording.RunCalculator? calculator,
  ]) => {
    ...run.result!,
    if ((run.result!['stats']?['version'] != RunResultStats.currentVersion) &&
        run.inputsLoaded &&
        run.inputs.isNotEmpty)
      'stats': (calculator ?? recording.RunCalculator.replay(run.inputs))
          .resultStats(run.inputs)
          .toJson(),
  };

  void _updatePaces(
    recording.LocalRun run,
    recording.RunMetrics metrics,
    String? notice,
  ) {
    final available = metrics.currentPaceSecondsPerKm != null;
    final changed =
        _paceRunId != run.id ||
        _pacePhase != run.phase ||
        _paceSignal != notice ||
        _paceStationary != metrics.stationary ||
        _paceAvailable != available;
    if (!changed && metrics.elapsedMs ~/ 3000 == _paceMs ~/ 3000) return;
    _paceRunId = run.id;
    _pacePhase = run.phase;
    _paceSignal = notice;
    _paceStationary = metrics.stationary;
    _paceAvailable = available;
    _paceMs = metrics.elapsedMs;
    _averagePace =
        metrics.distanceM >= 25 || run.phase == recording.RunPhase.ended
        ? metrics.paceSecondsPerKm
        : null;
    final current = run.phase == recording.RunPhase.running && notice == null
        ? metrics.currentPaceSecondsPerKm
        : null;
    _currentPace = current == null ? null : (current / 5).round() * 5.0;
  }

  RunSnapshot _fromRun(
    recording.LocalRun run,
    recording.RunMetrics metrics,
    recording.RunCalculator calculator, {
    String? notice,
    bool live = true,
  }) {
    if (run.phase == recording.RunPhase.ended && run.result != null) {
      return remoteRunSnapshot(_withLocalStats(run, calculator));
    }
    if (live) _updatePaces(run, metrics, notice);
    return RunSnapshot(
      state: switch (run.phase) {
        recording.RunPhase.running => RunState.running,
        recording.RunPhase.paused => RunState.paused,
        recording.RunPhase.ended => RunState.finished,
      },
      sessionId: run.id,
      startedAt: run.startedAt,
      elapsed: Duration(milliseconds: metrics.elapsedMs),
      active: Duration(milliseconds: metrics.activeMs),
      moving: Duration(milliseconds: metrics.movingMs),
      paceDisplayManaged: true,
      averagePaceDisplay: live ? _averagePace : metrics.paceSecondsPerKm,
      currentPaceDisplay: live ? _currentPace : null,
      stationary: metrics.stationary,
      laps: calculator.lapsAt(metrics.elapsedMs),
      resultStats: run.phase == recording.RunPhase.ended
          ? calculator.resultStats(run.inputs)
          : null,
      liveElevationGainM: run.phase != recording.RunPhase.ended
          ? calculator.liveElevationStats(run.inputs).elevationGainM
          : null,
      voiceNotice: live ? _recording?.voiceNotice : null,
      averageCadence: metrics.averageCadence,
      currentCadence: metrics.currentCadence,
      cadenceCoverageMs: metrics.cadenceCoverageMs,
      cadenceStatus: live
          ? (_recording?.cadenceStatus ?? '센서 미연결')
          : metrics.averageCadence == null
          ? '측정 없음'
          : '측정 완료',
      distanceMeters: metrics.distanceM,
      inputs: run.inputs
          .map(
            (input) => RunInput(
              seq: input.seq,
              kind: RunInputKind.values.byName(input.kind.name),
              elapsedMs: input.elapsedMs,
              measuredAt: input.measuredAt,
              accuracyM: input.accuracyM,
              point: input.lat == null
                  ? null
                  : RunPoint(input.lat!, input.lng!),
            ),
          )
          .toList(),
      gpsStatus: notice != null
          ? '신호 확인 중'
          : metrics.stationary
          ? '정지 감지'
          : run.inputs.any((p) => p.good)
          ? '위치 수신 중'
          : 'GPS 신호 대기',
      storageStatus: run.phase != recording.RunPhase.ended
          ? '기기에 저장 중'
          : metrics.distanceM <= 0
          ? '측정 거리 없음'
          : run.pending
          ? switch (run.syncState) {
              'blocked' => '기기 저장 · 동기화 확인 필요',
              'processing' => '기기 저장 · 서버 처리 중',
              'uploading' => '기기 저장 · 전송 중',
              _ => '기기 저장',
            }
          : '서버 저장 완료',
      notice: notice,
      endReason: run.endReason,
      gapCount: metrics.gapCount,
      segments: calculator.segments
          .map(
            (segment) => segment.map((p) => RunPoint(p.lat!, p.lng!)).toList(),
          )
          .toList(),
    );
  }

  void prepareStart() {
    if (_recording != null) {
      unawaited(_recording!.prepareStart());
      return;
    }
    if (snapshot.state != RunState.ready || countdown != null) return;
    _countdown = 3;
    notifyListeners();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown == 1) {
        timer.cancel();
        _countdown = null;
        _session.start(createId!());
        // The timer only redraws. Elapsed time comes from the monotonic clock.
        _refreshTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => notifyListeners(),
        );
      } else {
        _countdown = countdown! - 1;
      }
      notifyListeners();
    });
  }

  void cancelStart() {
    if (_recording != null) {
      _recording!.cancelStart();
      return;
    }
    _countdownTimer?.cancel();
    _countdown = null;
    notifyListeners();
  }

  void pause() {
    if (_recording != null) {
      unawaited(_recording!.pause());
      return;
    }
    if (snapshot.state != RunState.running) return;
    _session.pause();
    notifyListeners();
  }

  void resume() {
    if (_recording != null) {
      unawaited(_recording!.resume());
      return;
    }
    if (snapshot.state != RunState.paused) return;
    _session.resume();
    notifyListeners();
  }

  Future<void> finish() async {
    if (_recording != null) {
      await _recording!.end();
      return;
    }
    if (snapshot.state != RunState.paused) return;
    _session.finish();
    _refreshTimer?.cancel();
    notifyListeners();
  }

  void newRun() {
    if (snapshot.state != RunState.finished) return;
    discard();
  }

  void discard() {
    if (_recording != null) {
      _recording!.clearResult();
      return;
    }
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    _countdown = null;
    _session = createSession!();
    notifyListeners();
  }

  @override
  void dispose() {
    _recording?.removeListener(notifyListeners);
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void setEndConfirmation(bool open) => _recording?.setEndConfirmation(open);
}
