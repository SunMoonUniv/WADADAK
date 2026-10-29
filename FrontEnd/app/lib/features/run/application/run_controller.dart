import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/token_storage.dart';
import '../../../core/api/run_api_client.dart';
import '../data/run_local_store.dart';
import '../../../core/location/location_service.dart';
import '../../../core/map/geo_point.dart';
import '../../../core/permissions/device_setup.dart';
import '../../../core/time/monotonic_clock.dart';
import '../domain/run_location_policy.dart';
import '../data/run_audio_output.dart';
import 'audio_guide.dart';
import 'course_run_entry.dart';
import '../data/run_device.dart';
import '../domain/run_voice.dart';
import '../domain/course_run.dart';
import '../domain/course_tracker.dart';
import '../domain/route_guidance.dart';
import '../domain/recording_models.dart';
import 'run_recorder.dart';
import 'run_sync_worker.dart';
import 'ghost_start_flow.dart';
import '../data/ghost_start_api.dart';
import '../domain/ghost_run.dart';
import '../domain/own_ghost.dart';
import '../domain/free_ghost.dart';

final runControllerProvider = Provider<RunController>((ref) {
  final controller = RunController(
    RunLocalStore(),
    LocationService(),
    RunApiClient(ref.read(dioProvider)),
    () async => (await ref.read(tokenStorageProvider).read())?.memberId,
    device: RunDevice(),
  );
  ref.listen(authControllerProvider, (_, next) {
    if (next.value is SignedIn) {
      unawaited(controller.bindOwner());
    }
    if (next.value is SignedOut) {
      unawaited(controller.accountChanged());
    }
  });
  // 코스 상세의 `이 코스로 달리기`(F6). 받아 가고 비워 같은 코스를 다시 골라도 다시 받는다
  ref.listen(selectedCourseProvider, (_, next) {
    if (next == null) return;
    controller.selectCourse(next);
    Future.microtask(
      () => ref.read(selectedCourseProvider.notifier).select(null),
    );
  }, fireImmediately: true);
  ref.onDispose(controller.dispose);
  unawaited(controller.bindOwner());
  return controller;
});

class RunController extends ChangeNotifier with WidgetsBindingObserver {
  RunController(
    this.store,
    this.location,
    this.api,
    this.owner, {
    Future<void> Function(Duration)? wait,
    DateTime Function()? utcNow,
    AppLifecycleState? Function()? lifecycleState,
    bool automaticTicks = true,
    this.device,
    AudioGuide? audio,
    Future<int> Function()? nowMs,
    Future<RunClockSample> Function()? recoveryClock,
    GhostStartSource? ghostApi,
  }) : audioGuide = audio ?? AudioGuide(RunAudioOutput()),
       _wait = wait ?? Future<void>.delayed,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _lifecycleState =
           lifecycleState ?? (() => WidgetsBinding.instance.lifecycleState) {
    audioGuide.onChanged = _notify;
    final clock = MonotonicClock();
    _recoveryClock =
        recoveryClock ??
        (nowMs == null
            ? clock.sample
            : () async => RunClockSample(await nowMs(), null));
    recorder = RunRecorder(
      store,
      nowMs ?? clock.nowMs,
      recoveryClock: _recoveryClock,
    );
    ghostStarts = GhostStartFlow(
      store,
      ghostApi ?? GhostStartApi(api),
      recorder,
      _recoveryClock,
      () async => _disposed ? null : await owner(),
    );
    syncWorker = RunSyncWorker(
      api,
      store,
      owner,
      canSync: () => !preparing && !recorder.active && !_disposed,
    );
    _changes = recorder.changes.stream.listen((_) {
      _checkCourseEnd();
      _guide();
      _notify();
      unawaited(_refreshExtras());
    });
    if (automaticTicks) {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refreshMeasurement()),
      );
    }
    WidgetsBinding.instance.addObserver(this);
  }
  final RunLocalStore store;
  final LocationService location;
  final RunDevice? device;
  RunVoiceSettings voiceSettings = const RunVoiceSettings();
  final AudioGuide audioGuide;
  String cadenceStatus = '측정 전';
  String? get voiceNotice => audioGuide.notice;
  Set<String> deletedIds = {};
  int pendingDeleteCount = 0;
  int pendingGhostClosureCount = 0;
  String? _deviceRunId;
  bool _pressureStarted = false;
  Completer<void>? _syncDone;
  Future<void>? _extrasJob;
  final RunApiClient api;
  final Future<String?> Function() owner;
  late final RunRecorder recorder;
  late final RunSyncWorker syncWorker;
  late final GhostStartFlow ghostStarts;
  late final Future<RunClockSample> Function() _recoveryClock;
  PreparedFreeGhost? selectedFreeGhost;
  PreparedCourseGhost? _selectedGhost;
  PreparedCourseGhost? get selectedGhost => _selectedGhost;
  set selectedGhost(PreparedCourseGhost? value) {
    _selectedGhost = value;
    selectedFreeGhost = null;
  }

  CourseSnapshot? _ghostPreparation;
  int _ghostSelectionGeneration = 0;
  bool hasPendingGhostStart = false;
  Timer? _timer;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _utcNow;
  final AppLifecycleState? Function() _lifecycleState;
  late final StreamSubscription<void> _changes;
  StreamSubscription<Position>? _gps;

  /// 코스 상세에서 고른 코스. 다음 시작을 코스 러닝으로 한다(F6)
  CourseSelection? selectedCourse;

  /// 코스 러닝 준비를 마치고 측정 전(RCR-01). 지도에 출발점까지 안내하고 반경 안에서만 시작한다
  CourseStart? courseStart;
  CourseStartIntent? _liveCourseIntent;
  StreamSubscription<Position>? _approach;

  /// 마지막으로 시작한 코스 러닝의 코스와 세션 ID. 결과 화면의 "서버 판정 대기"에 쓴다
  CourseSelection? course;
  String? courseRunId;

  /// 경로 추적은 원본에서 재구성한다. 승인된 고스트만 신뢰 가능한 60초 이내에 재개한다.
  CourseTracker? courseTracker;

  /// 그 코스 러닝의 이탈 안내(6·7장). 안내 전용이고 판정에는 영향이 없다
  RouteGuidance? routeGuidance;

  /// 코스 구간을 끝낸 사유(`ROUTE_END` 경로 끝 도착·`COURSE_ONLY` 코스만 종료). 이후 같은 세션은 자유 러닝이다(RUN-07·RUN-08)
  String? courseEndReason;

  /// 경로 끝 도착 감지 오차(m). 서버 끝 도달 오차(30m)가 이보다 넉넉해야 한다(정책 5.3). 주행 검증 전 개발값
  static const courseArrivalM = 20.0;

  /// 진행 중인 러닝이 아직 코스 구간이다
  bool get onCourse =>
      courseRunId != null &&
      run?.id == courseRunId &&
      recorder.active &&
      courseEndReason == null;
  List<LocalRun> records = [];
  List<Map<String, dynamic>> remoteRecords = [];
  String? currentOwner, error, gpsNotice, nextCursor, historyNotice;
  String? ghostStartRejection;
  void acknowledgeGhostStartRejection() {
    ghostStartRejection = null;
    _notify();
  }

  int? countdown;
  bool preparing = false, syncing = false, loadingHistory = false;
  bool _disposed = false, _ticking = false, _syncDisabled = false;
  Future<void>? _binding, _shutdown;
  DeviceSettingsAction? setupAction;
  bool _committing = false;
  bool storageFault = false;
  int _generation = 0, _ticks = 0, _locationGeneration = 0;
  int _networkFailures = 0;
  DateTime? _retryAt;
  Position? _latest;
  DateTime? _lastFixAt;
  bool _gapOpen = false;
  LocalRun? get run =>
      recorder.current?.owner == currentOwner ? recorder.current : null;
  bool get canCancelStart => preparing && !_committing;
  RunMetrics get metrics => recorder.metrics;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> bindOwner() {
    if (_disposed) return Future.value();
    return _binding ??= _bindOwner().whenComplete(() => _binding = null);
  }

  Future<void> _bindOwner() async {
    try {
      while (!_disposed) {
        final member = await owner();
        if (member == currentOwner) return;
        final previousOwner = currentOwner;
        if (previousOwner != null) {
          for (final pending in await store.pendingCourseStarts(
            previousOwner,
          )) {
            await store.deleteRecord(previousOwner, pending.id);
          }
          for (final pending in await store.pendingGhostStarts(previousOwner)) {
            await store.deleteRecord(previousOwner, pending.intent.id);
          }
        }
        cancelStart();
        cancelCourseStart();
        await _stopWatchingStart();
        courseStart = null;
        _liveCourseIntent = null;
        if (previousOwner != null) {
          selectedCourse = null;
        }
        course = null;
        courseRunId = null;
        courseTracker = null;
        routeGuidance = null;
        courseEndReason = null;
        currentOwner = null;
        ghostStartRejection = null;
        selectedGhost = null;
        _ghostPreparation = null;
        _ghostSelectionGeneration++;
        hasPendingGhostStart = false;
        records = [];
        remoteRecords = [];
        _notify();
        if (recorder.active) await recorder.end(reason: 'ACCOUNT_CHANGED');
        await _stopLocation();
        await _stopExtras();
        recorder.current = null;
        recorder.calculator = RunCalculator();
        recorder.elapsedMs = 0;
        currentOwner = member;
        _syncDisabled = false;
        _networkFailures = 0;
        _retryAt = null;
        error = null;
        setupAction = null;
        records = [];
        remoteRecords = [];
        nextCursor = null;
        historyNotice = null;
        deletedIds = {};
        pendingDeleteCount = 0;
        pendingGhostClosureCount = 0;
        voiceSettings = const RunVoiceSettings();
        if (member == null) return;
        voiceSettings = await store.voiceSettings(member);
        audioGuide.restoreSettings(voiceSettings);
        deletedIds = await store.deletedIds(member);
        pendingDeleteCount = (await store.pendingDeletions(member)).length;
        pendingGhostClosureCount = (await store.pendingGhostClosures(member))
            .length;
        records = (await recorder.recover(member, summaryOnly: true))
            .where(
              (r) =>
                  (r.summary?['metrics']?['distanceM'] as num? ??
                      RunCalculator.replay(r.inputs).distanceM) >
                  0,
            )
            .toList();
        if (await owner() != member) {
          records = [];
          continue;
        }
        if (!recorder.active) {
          try {
            await ghostStarts.recover(member);
          } on GhostStartRejected catch (e) {
            await _operationError(e);
          } on ApiException catch (e) {
            error = e.message;
          }
        }
        hasPendingGhostStart = (await store.pendingGhostStarts(member))
            .isNotEmpty;
        if (await owner() != member) continue;
        await _restoreGhostRun();
        await _restoreCourseStart(member);
        remoteRecords = [];
        nextCursor = null;
        _notify();
        unawaited(sync());
        unawaited(loadHistory());
        return;
      }
    } on Object catch (e) {
      await _operationError(e);
    } finally {
      _notify();
    }
  }

  Future<void> accountChanged() => bindOwner();

  /// 코스 러닝으로 시작할 코스를 고른다. 진행 중인 러닝이 있으면 바꾸지 않는다(RUN-05)
  void selectCourse(CourseSelection selection) {
    if (recorder.active ||
        preparing ||
        courseStart != null ||
        hasPendingGhostStart) {
      return;
    }
    selectedCourse = selection;
    selectedGhost = null;
    _ghostPreparation = null;
    _ghostSelectionGeneration++;
    error = null;
    _notify();
  }

  void clearCourse() {
    if (recorder.active ||
        preparing ||
        courseStart != null ||
        hasPendingGhostStart) {
      return;
    }
    selectedCourse = null;
    selectedGhost = null;
    _ghostPreparation = null;
    _ghostSelectionGeneration++;
    _notify();
  }

  bool get canSelectGhost =>
      recorder.current == null &&
      !preparing &&
      courseStart == null &&
      !hasPendingGhostStart;

  void clearGhost() {
    if (!canSelectGhost) return;
    selectedGhost = null;
    _ghostPreparation = null;
    _ghostSelectionGeneration++;
    _notify();
  }

  /// Read the existing course preparation identity without starting/counting a duel.
  /// The same snapshot/session is reused when the selected ghost reaches the start flow.
  Future<({String owner, CourseSnapshot snapshot})>
  prepareGhostSelection() async {
    await bindOwner();
    final selection = selectedCourse, member = currentOwner;
    if (!canSelectGhost || selection == null || member == null) {
      throw StateError('고스트를 선택할 수 없는 상태예요.');
    }
    final generation = ++_ghostSelectionGeneration;
    final id = const Uuid().v7();
    final snapshot = CourseSnapshot.fromJson(
      await api.prepareCourse(member, id, selection.courseId),
    );
    final activeOwner = await owner();
    if (_disposed ||
        generation != _ghostSelectionGeneration ||
        !canSelectGhost ||
        activeOwner != member ||
        currentOwner != member ||
        !identical(selectedCourse, selection)) {
      throw StateError('계정 또는 코스가 바뀌었어요.');
    }
    if (snapshot.sessionId != id ||
        snapshot.courseId != selection.courseId ||
        snapshot.version == null ||
        snapshot.version! < 0 ||
        snapshot.route.length < 2 ||
        snapshot.totalDistanceMeters <= 0) {
      throw const FormatException('Invalid ghost course preparation');
    }
    _ghostPreparation = snapshot;
    return (owner: member, snapshot: snapshot);
  }

  /// 코스 러닝 서버 연결(D-08). 끊겨 있으면 시작하지 않고 연결 실패를 알린다
  Future<T> _courseCall<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      if (e.code == ApiException.network) {
        throw const DeviceSetupException(
          '인터넷에 연결되지 않아 코스 러닝을 시작할 수 없어요. 연결을 확인하고 다시 시도해 주세요.',
        );
      }
      rethrow;
    }
  }

  /// 자유 러닝은 카운트다운 뒤 측정. 코스 러닝은 두 번 부른다(RCR-01):
  /// 처음은 준비까지 하고 측정 전([courseStart])에 멈추고, 출발점 반경 안에서 다시 부르면 카운트다운 뒤 측정.
  Future<void> prepareStart() async {
    if (preparing || recorder.active || storageFault || _disposed) return;
    await bindOwner();
    if (hasPendingGhostStart) {
      await retryGhostStart();
      return;
    }
    if (preparing || recorder.active || storageFault || _disposed) return;
    final member = await owner();
    if (member == null) {
      error = '로그인 후 시작해 주세요.';
      _notify();
      return;
    }
    final start = courseStart;
    if (start != null && start.intent == null && !start.nearStart) return;
    final generation = ++_generation;
    // 코스 러닝은 세션 ID를 먼저 만들어 서버 준비·시작 신호와 기록에 같은 ID를 쓴다
    final selection = start == null ? selectedCourse : null;
    final freeGhost = selectedFreeGhost;
    final ghostPreparation =
        freeGhost != null || selection != null && selectedGhost != null
        ? _ghostPreparation
        : null;
    final runId =
        start?.runId ?? ghostPreparation?.sessionId ?? const Uuid().v7();
    preparing = true;
    error = null;
    setupAction = null;
    gpsNotice = null;
    int? locationToken;
    _notify();
    try {
      await _syncDone?.future;
      if (generation != _generation || _disposed) return;
      await device?.requestPermission();
      if (generation != _generation || _disposed) return;
      await audioGuide.prepare(voiceSettings);
      if (generation != _generation || _disposed) return;
      if (!location.supportsBackgroundTracking) {
        throw const DeviceSetupException('첫 러닝 버전은 Android에서 사용할 수 있어요.');
      }
      await location.ensurePermission(precise: true);
      final position = await location.currentPosition();
      if (generation != _generation || _disposed) return;
      if (_lifecycleState() != AppLifecycleState.resumed) {
        throw const DeviceSetupException('앱으로 돌아온 뒤 러닝을 시작해 주세요.');
      }
      if (selection != null || freeGhost != null && start == null) {
        // 코스 공개 여부 확인과 판정용 경로 저장. 실패하면 시작하지 않는다(D-08)
        final snapshot =
            ghostPreparation ??
            CourseSnapshot.fromJson(
              await _courseCall(
                () => api.prepareCourse(member, runId, selection!.courseId),
              ),
            );
        final ghost = selectedGhost;
        if (ghost != null &&
            (ghost.owner != member ||
                snapshot.courseId != ghost.course.id ||
                snapshot.version != ghost.course.version)) {
          throw StateError('코스가 바뀌었어요. 고스트를 다시 선택해 주세요.');
        }
        if (generation != _generation || _disposed) return;
        courseStart = CourseStart(
          runId,
          selection,
          snapshot,
          GeoPoint(position.latitude, position.longitude),
        );
        _watchStart();
        return;
      }
      await _stopWatchingStart();
      _latest = position;
      _lastFixAt = _utcNow();
      _gapOpen = false;
      locationToken = _startLocation();
      for (var value = start?.intent == null ? 3 : 0; value > 0; value--) {
        if (generation != _generation || _disposed) return;
        countdown = value;
        _notify();
        await _wait(const Duration(seconds: 1));
      }
      if (generation != _generation || _disposed || await owner() != member) {
        return;
      }
      if (_lifecycleState() != AppLifecycleState.resumed) {
        return;
      }
      if (_latest == null || !RunLocationPolicy.usable(_latest!, _utcNow())) {
        throw const DeviceSetupException('GPS 신호가 약해요. 다시 시작해 주세요.');
      }
      if (device != null && !await device!.permissionGranted()) {
        throw const DeviceSetupException(
          '신체 활동 권한을 허용한 뒤 시작해 주세요.',
          action: DeviceSettingsAction.appSettings,
        );
      }
      if (generation != _generation || _disposed || await owner() != member) {
        return;
      }
      if (start != null && start.intent == null) {
        start.position = GeoPoint(_latest!.latitude, _latest!.longitude);
        if (!start.nearStart) {
          throw const DeviceSetupException('출발점 20m 안으로 이동한 뒤 다시 시작해 주세요.');
        }
      }
      var startedAt = _utcNow();
      int? courseOriginMs;
      final ghost = selectedGhost;
      if ((ghost != null || freeGhost != null) && start != null) {
        _committing = true;
        countdown = null;
        hasPendingGhostStart = true;
        _notify();
        final reading = await _recoveryClock();
        final intent = GhostStartIntent(
          owner: member,
          id: runId,
          startedAt: startedAt,
          course: start.snapshot,
          sourceId: freeGhost?.replay.sourceId ?? ghost!.sourceId,
          sourceSeconds: freeGhost?.replay.seconds ?? ghost!.seconds,
          publicPeriod: ghost?.publicPeriod,
          referenceHash: freeGhost?.referenceHash,
          playbackVersion: freeGhost?.replay.playback.version,
          clock: reading,
        );
        final continued = await ghostStarts.begin(intent);
        hasPendingGhostStart = (await store.pendingGhostStarts(member))
            .isNotEmpty;
        if (!continued) {
          error = hasPendingGhostStart
              ? '같은 고스트 시작을 확인하고 있어요. 연결 후 다시 시도해 주세요.'
              : '중단된 대결은 마지막 저장 지점에서 마감했어요.';
          return;
        }
      } else if (start != null) {
        // Save the exact request and monotonic origin before sending an irreversible start signal.
        _committing = true;
        countdown = null;
        _notify();
        var intent = start.intent;
        if (intent == null) {
          final clock = await _recoveryClock();
          startedAt = _utcNow();
          intent = CourseStartIntent(
            member,
            runId,
            startedAt,
            start.snapshot,
            clock,
          );
          try {
            await store.saveCourseIntent(intent);
          } on Object catch (e) {
            throw RunStorageFailure(e);
          }
          start.intent = intent;
          _liveCourseIntent = intent;
        }
        startedAt = intent.startedAt;
        await _checkCourseIntent(intent);
        if (generation != _generation || _disposed || await owner() != member) {
          return;
        }
        await _courseCall(() => api.startCourse(member, runId, startedAt));
        if (generation != _generation || _disposed || await owner() != member) {
          return;
        }
        await _checkCourseIntent(intent);
        if (_lifecycleState() != AppLifecycleState.resumed) {
          throw const DeviceSetupException('앱으로 돌아온 뒤 코스 시작을 다시 확인해 주세요.');
        }
        courseOriginMs = intent.clock.elapsedMs;
      }
      _committing = true;
      countdown = null;
      _notify();
      if (ghost == null && freeGhost == null) {
        await recorder.start(
          runId,
          member,
          startedAt,
          originMs: courseOriginMs,
        );
        _liveCourseIntent = null;
      }
      course = start?.course;
      courseRunId = start == null ? null : runId;
      final geometry = start == null
          ? null
          : RouteGeometry(start.snapshot.route, breaks: start.snapshot.breaks);
      courseTracker = geometry == null
          ? null
          : CourseTracker(
              geometry,
              freeGhostV2: recorder.current?.ghost?.intent.freeGhostV2 == true,
            );
      routeGuidance = geometry == null ? null : RouteGuidance(geometry);
      courseEndReason = null;
      courseStart = null;
      selectedCourse = null;
      selectedGhost = null;
      _ghostPreparation = null;
      _ghostSelectionGeneration++;
      currentOwner = member;
      if (_disposed || await owner() != member) {
        await recorder.end(reason: 'ACCOUNT_CHANGED');
        await bindOwner();
        return;
      }
      await _refreshExtras();
      final latest = _latest!;
      if (!RunLocationPolicy.usable(latest, _utcNow())) {
        await _markGap('START_WAIT');
        return;
      }
      await recorder.gps(
        latest.latitude,
        latest.longitude,
        latest.accuracy,
        measuredAt: latest.timestamp,
        speedMps: latest.speed,
        speedAccuracyMps: latest.speedAccuracy,
        altitudeM: latest.hasAltitude ? latest.altitude : null,
        altitudeAccuracyM: latest.hasAltitudeAccuracy
            ? latest.altitudeAccuracy
            : null,
      );
    } on Object catch (e) {
      if (generation == _generation) await _operationError(e);
    } finally {
      if (generation == _generation) {
        preparing = false;
        countdown = null;
      }
      _committing = false;
      if (!recorder.active && locationToken != null) {
        await _stopLocation(expectedToken: locationToken);
      }
      // 코스 러닝 시작이 실패하면 측정 전으로 돌아가 다시 출발점을 안내한다
      if (!recorder.active &&
          courseStart != null &&
          !_disposed &&
          _lifecycleState() == AppLifecycleState.resumed) {
        _watchStart();
      }
      _notify();
    }
  }

  void cancelStart() {
    if (recorder.active || _committing) return;
    ++_generation;
    countdown = null;
    preparing = false;
    unawaited(
      _stopLocation().then((_) {
        if (courseStart != null && !_disposed) _watchStart();
      }),
    );
    _notify();
  }

  /// Entry adapter for the existing own-ghost selection component. Uses the F6 preparation flow.
  void selectFreeGhost(PreparedFreeGhost prepared) {
    if (!canSelectGhost || prepared.owner != currentOwner) {
      throw StateError('고스트 선택을 다시 확인해 주세요.');
    }
    final reference = prepared.reference;
    selectedCourse = null;
    selectedGhost = null;
    _ghostPreparation = CourseSnapshot(
      sessionId: const Uuid().v7(),
      route: reference.route,
      totalDistanceMeters: reference.totalDistanceMeters,
      name: reference.name,
      version: reference.version,
      breaks: reference.breaks,
    );
    selectedFreeGhost = prepared;
    _ghostSelectionGeneration++;
    error = null;
    _notify();
  }

  /// Entry adapter for the existing own-ghost selection component. Uses the F6 preparation flow.
  void selectGhost(PreparedCourseGhost prepared) {
    if (!canSelectGhost) {
      return;
    }
    if (prepared.owner != currentOwner ||
        prepared.replay.sourceId != prepared.sourceId ||
        !prepared.replay.playback.eligible) {
      throw StateError('고스트 선택을 다시 확인해 주세요.');
    }
    final data =
        (jsonDecode(prepared.replay.payloadJson) as Map)['course'] as Map;
    selectedCourse = CourseSelection(
      prepared.course.id,
      data['name'] as String? ?? '고스트 대결',
    );
    selectedGhost = prepared;
    _ghostSelectionGeneration++;
    error = null;
    _notify();
  }

  Future<void> retryGhostStart() async {
    final member = currentOwner;
    if (member == null ||
        preparing ||
        recorder.active ||
        storageFault ||
        _disposed) {
      return;
    }
    preparing = true;
    try {
      await ghostStarts.recover(member);
      if (await owner() != member || _disposed) return;
      hasPendingGhostStart = (await store.pendingGhostStarts(member))
          .isNotEmpty;
      await _restoreGhostRun();
      if (hasPendingGhostStart) error = '같은 고스트 시작을 확인하고 있어요. 연결 후 다시 시도해 주세요.';
    } on Object catch (e) {
      await _operationError(e);
    } finally {
      preparing = false;
      _notify();
    }
    if (!recorder.active) unawaited(sync());
  }

  Future<void> _restoreGhostRun() async {
    final current = recorder.current, context = recorder.current?.ghost;
    if (!recorder.active || current?.owner != currentOwner || context == null) {
      return;
    }
    await _stopWatchingStart();
    if (_disposed || await owner() != current!.owner) return;
    final snapshot = context.intent.course;
    course = snapshot.courseId == null
        ? null
        : CourseSelection(snapshot.courseId!, snapshot.name ?? '고스트 대결');
    courseRunId = current.id;
    courseStart = null;
    selectedCourse = null;
    selectedGhost = null;
    final segment = current.inputs
        .where((i) => i.kind == RunKind.segmentEnd)
        .firstOrNull;
    courseEndReason =
        segment?.reason ?? (segment == null ? null : 'COURSE_ONLY');
    final geometry = RouteGeometry(snapshot.route, breaks: snapshot.breaks);
    final courseInputs = current.inputs
        .takeWhile((i) => i.kind != RunKind.segmentEnd)
        .toList();
    courseTracker = CourseTracker(
      geometry,
      freeGhostV2: context.intent.freeGhostV2,
    )..feed(courseInputs);
    routeGuidance = RouteGuidance(geometry)..feed(courseInputs);
    routeGuidance!.alertOpen = false; // Do not replay historical alerts/audio.
    _latest = null;
    _lastFixAt = null;
    _gapOpen = true;
    gpsNotice = '대결을 이어가고 있어요. 새 GPS 신호를 기다려요.';
    if (_gps == null) _startLocation();
    unawaited(_refreshExtras());
  }

  /// 경로 끝 도착(RUN-08): 코스를 따라간 위치가 끝 [courseArrivalM] 안이면 코스 구간을 끝낸다.
  /// 좌표가 아니라 코스상 위치로 보므로 순환·왕복 코스의 출발점을 끝으로 보지 않는다. 완주는 서버가 판정한다
  void _checkCourseEnd() {
    final tracker = courseTracker, current = run;
    if (!onCourse ||
        tracker == null ||
        current == null ||
        current.phase != RunPhase.running) {
      return;
    }
    tracker.feed(current.inputs);
    final position = tracker.positionM;
    if (position != null && position >= tracker.route.length - courseArrivalM) {
      unawaited(endCourse('ROUTE_END'));
    }
  }

  /// 이탈 안내(6·7장): 새 입력으로 이탈·복귀를 판단해 음성을 내고 팝업 상태를 바꾼다. 코스 구간이 끝나면 멈추고 팝업을 닫는다
  void _guide() {
    final guidance = routeGuidance, current = run;
    if (guidance == null || current == null) return;
    if (!onCourse) {
      guidance.alertOpen = false;
      return;
    }
    for (final cue in guidance.feed(current.inputs)) {
      switch (cue) {
        case GuidanceCue.candidate:
          unawaited(audioGuide.announce('코스에서 벗어나고 있어요'));
        case GuidanceCue.alert:
          unawaited(audioGuide.announce('코스를 벗어났어요'));
        case GuidanceCue.dismiss:
          break;
      }
    }
  }

  /// 이탈 팝업을 띄울 때(7.1). 진동은 팝업과 함께 화면이 낸다
  bool get deviationAlert => onCourse && (routeGuidance?.alertOpen ?? false);

  /// 이탈 팝업 [확인]: 이탈이 이어지면 30초 뒤 다시 안내한다
  void acknowledgeDeviation() {
    routeGuidance?.acknowledge(recorder.elapsedMs);
    _notify();
  }

  /// 이탈 팝업 [다시 표시하지 않음]: 이번 러닝 끝까지 이탈 팝업·진동·음성을 끈다
  void muteDeviation() {
    routeGuidance?.mute();
    _notify();
  }

  /// 코스 구간을 끝내고 같은 세션을 자유 러닝으로 잇는다(경로 끝 도착·코스만 종료, RUN-07·RUN-08).
  /// 기록에 `SEGMENT_END`를 남기고 구간 종료 신호(현재 러너 수)를 보낸다. 신호가 실패해도 서버가 업로드 때 뺀다
  Future<void> endCourse(String reason) async {
    final id = courseRunId, member = currentOwner, tracker = courseTracker;
    if (!onCourse || id == null || member == null) return;
    courseEndReason = reason;
    _notify();
    try {
      await recorder.segmentEnd(reason);
    } on Object catch (e) {
      await _operationError(e);
      return;
    }
    if (run?.ghost?.intent.isFree != true) {
      unawaited(() async {
        try {
          await api.segmentEnd(member, id);
        } on Object {
          // 현재 러너 수는 업로드 도착·3시간 뒤에도 빠진다
        }
      }());
    }
    if (reason == 'ROUTE_END' && tracker != null) {
      // 측정 시작(START)이 0ms라 구간 종료 시각이 곧 코스 총 소요시간
      final ms =
          run?.inputs
              .where((i) => i.kind == RunKind.segmentEnd)
              .lastOrNull
              ?.elapsedMs ??
          0;
      unawaited(
        audioGuide.announce(courseArrivalVoice(ms, tracker.route.length)),
      );
    }
  }

  /// AUD-06: 기기에서 잰 코스 총 소요시간(정지 포함)과 그 시간 ÷ 코스 거리 페이스. 결과 화면은 서버 판정 값을 쓴다
  static String courseArrivalVoice(int elapsedMs, double lengthM) {
    final seconds = elapsedMs ~/ 1000;
    final pace = lengthM <= 0 ? 0 : (seconds / (lengthM / 1000)).round();
    return '코스 끝에 도착했어요. 걸린 시간 ${seconds ~/ 60}분 ${seconds % 60}초, '
        '평균 페이스 ${pace ~/ 60}분 ${pace % 60}초입니다. 자유 러닝으로 이어서 기록해요.';
  }

  /// 측정 전 화면에서 나간다. 고른 코스는 남겨 준비 화면(C6)으로 돌아간다.
  /// 서버에 남은 준비만 한 시도는 지우지 않는다(서버 연결 문서 7장)
  void cancelCourseStart() {
    if (preparing || courseStart == null) return;
    final intent = courseStart!.intent;
    if (intent != null) {
      preparing = true;
      unawaited(() async {
        try {
          await _cancelCourseIntent(intent);
        } on Object catch (e) {
          await _operationError(e);
        } finally {
          preparing = false;
          _notify();
          unawaited(sync());
        }
      }());
      return;
    }
    courseStart = null;
    unawaited(_stopWatchingStart());
    _notify();
  }

  Future<void> _cancelCourseIntent(CourseStartIntent intent) async {
    await store.deleteRecord(intent.owner, intent.id);
    if (currentOwner != intent.owner) return;
    if (courseStart?.runId == intent.id) courseStart = null;
    _liveCourseIntent = null;
    await _stopWatchingStart();
    await _reloadLocal();
    _notify();
    unawaited(sync());
  }

  Future<void> _checkCourseIntent(CourseStartIntent intent) async {
    final reading = await _recoveryClock();
    final age =
        reading.since(intent.clock) ??
        (identical(_liveCourseIntent, intent) &&
                reading.bootId == null &&
                intent.clock.bootId == null
            ? reading.elapsedMs - intent.clock.elapsedMs
            : null);
    if (age == null || age < 0 || age > 60000) {
      await _cancelCourseIntent(intent);
      throw const DeviceSetupException('중단된 코스 시작을 취소했어요. 다시 시작해 주세요.');
    }
  }

  Future<void> _restoreCourseStart(String member) async {
    if (recorder.active || _disposed) return;
    for (final intent in await store.pendingCourseStarts(member)) {
      if (await owner() != member || _disposed) return;
      final reading = await _recoveryClock();
      final age = reading.since(intent.clock);
      if (age == null || age > 60000) {
        await _cancelCourseIntent(intent);
        error = '중단된 코스 시작을 취소했어요. 다시 시작해 주세요.';
        continue;
      }
      final selection = CourseSelection(
        intent.snapshot.courseId!,
        intent.snapshot.name ?? '코스 러닝',
      );
      selectedCourse = selection;
      courseStart = CourseStart(
        intent.id,
        selection,
        intent.snapshot,
        intent.snapshot.route.first,
        intent: intent,
      );
      error = '코스 시작을 확인하지 못했어요. 다시 시도해 주세요.';
    }
  }

  /// 측정 전 현재 위치. 측정하지 않으므로 기록 중 알림 없이 화면이 켜진 동안만 받는다
  void _watchStart() {
    if (_approach != null) return;
    _approach = location
        .positions(
          settings: AndroidSettings(
            forceLocationManager: true,
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
          ),
        )
        .listen((p) {
          final start = courseStart;
          if (start == null ||
              _disposed ||
              !RunLocationPolicy.usable(p, _utcNow())) {
            return;
          }
          start.position = GeoPoint(p.latitude, p.longitude);
          _notify();
        }, onError: (Object e) => unawaited(_operationError(e)));
  }

  Future<void> _stopWatchingStart() async {
    final subscription = _approach;
    _approach = null;
    await subscription?.cancel();
  }

  int _startLocation() {
    final token = ++_locationGeneration;
    _gps = location
        .positions(
          settings: AndroidSettings(
            forceLocationManager: true,
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: '와다닥 러닝 기록 중',
              notificationText: '화면을 꺼도 러닝 기록을 저장하고 있어요.',
              notificationChannelName: '러닝 측정',
              enableWakeLock: true,
              setOngoing: true,
            ),
          ),
        )
        .listen(
          (p) => _onPosition(p, token),
          onError: (Object e) => unawaited(_locationError(e, token)),
          onDone: () {
            if (token != _locationGeneration || _disposed) return;
            _gps = null;
            unawaited(_markGap('STREAM_ENDED'));
          },
        );
    return token;
  }

  Future<void> _markGap(String reason) async {
    if (_gapOpen || !recorder.active || storageFault || _disposed) return;
    _gapOpen = true;
    gpsNotice = 'GPS 신호를 기다리고 있어요. 시간은 계속 측정해요.';
    try {
      await recorder.gap(reason);
    } on Object catch (e) {
      await _operationError(e);
    }
    _notify();
  }

  void _onPosition(Position p, int token) {
    if (storageFault || _disposed || token != _locationGeneration) return;
    if (!RunLocationPolicy.fresh(p, _utcNow())) {
      unawaited(_markGap('STALE_FIX'));
      return;
    }
    _latest = p;
    _lastFixAt = _utcNow();
    _gapOpen = false;
    gpsNotice = p.accuracy > 15 ? '위치 정확도가 낮아요. 이동을 확인할 수 있는 신호를 기다려요.' : null;
    if (recorder.active) {
      unawaited(
        recorder
            .gps(
              p.latitude,
              p.longitude,
              p.accuracy,
              measuredAt: p.timestamp,
              speedMps: p.speed,
              speedAccuracyMps: p.speedAccuracy,
              altitudeM: p.hasAltitude ? p.altitude : null,
              altitudeAccuracyM: p.hasAltitudeAccuracy
                  ? p.altitudeAccuracy
                  : null,
            )
            .catchError((Object e) => _operationError(e)),
      );
    }
    _notify();
  }

  Future<void> _locationError(Object e, int token) async {
    if (token != _locationGeneration || _disposed || storageFault) return;
    if (!recorder.active) {
      await _operationError(e);
      cancelStart();
      return;
    }
    try {
      final permission = await location.permission();
      if (token != _locationGeneration || _disposed) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        error = '위치 권한이 해제되어 러닝을 종료했어요. 저장한 기록은 보존되어 있어요.';
        setupAction = DeviceSettingsAction.appSettings;
        await recorder.end(reason: 'PERMISSION_REVOKED');
        await _stopLocation();
        await _stopExtras();
        await _reloadLocal();
        unawaited(sync());
      } else {
        // Keep the foreground service alive so GPS can recover while the screen is off.
        await _markGap('LOCATION_ERROR');
      }
    } on Object catch (failure) {
      await _operationError(failure);
    }
    _notify();
  }

  Future<void> refreshMeasurement() async {
    if (_ticking || _disposed || storageFault) return;
    _ticking = true;
    try {
      _ticks++;
      if (recorder.active) {
        await recorder.tick(persist: _ticks % 5 == 0);
        if (!_gapOpen &&
            _lastFixAt != null &&
            _utcNow().difference(_lastFixAt!).inSeconds > 10) {
          await _markGap('NO_FIX');
        }
        if (_gps == null &&
            _ticks % 5 == 0 &&
            _lifecycleState() == AppLifecycleState.resumed) {
          _startLocation();
        }
      }
      await _refreshExtras();
      if (_ticks % 15 == 0 &&
          hasPendingGhostStart &&
          _lifecycleState() == AppLifecycleState.resumed) {
        unawaited(retryGhostStart());
      }
      if (_ticks % 15 == 0 &&
          !_syncDisabled &&
          !syncing &&
          (pendingDeleteCount > 0 ||
              pendingGhostClosureCount > 0 ||
              records.any((r) => r.pending && r.syncState != 'blocked'))) {
        unawaited(sync());
      }
    } on Object catch (e) {
      await _operationError(e);
    } finally {
      _ticking = false;
    }
  }

  Future<void> pause() async {
    if (storageFault) return;
    try {
      try {
        await _sampleCadence(force: true);
      } on RunStorageFailure {
        rethrow;
      } on Object {
        cadenceStatus = '센서 연결 실패';
      }
      await _samplePressure();
      await recorder.pause();
      await audioGuide.stop();
      await _refreshExtras();
    } on Object catch (e) {
      await _operationError(e);
    }
  }

  Future<void> resume() async {
    if (storageFault) return;
    try {
      await recorder.resume();
      await _refreshExtras();
    } on Object catch (e) {
      await _operationError(e);
    }
  }

  Future<void> end() async {
    if (storageFault) return;
    try {
      await recorder.end();
      await _stopExtras();
      await _stopLocation();
      await _reloadLocal();
      if (metrics.distanceM <= 0) {
        error = '측정된 거리가 없어 기록을 저장하지 않았어요.';
      } else {
        unawaited(sync());
      }
    } on Object catch (e) {
      await _operationError(e);
    }
    _notify();
  }

  void setEndConfirmation(bool open) {
    recorder.confirmingEnd = open;
  }

  Future<void> _operationError(Object e) async {
    if (e is GhostStartRejected) {
      if (e.owner != currentOwner ||
          await owner() != e.owner ||
          recorder.active) {
        return;
      }
      hasPendingGhostStart = (await store.pendingGhostStarts(e.owner))
          .isNotEmpty;
      if (hasPendingGhostStart) return;
      await _stopWatchingStart();
      courseStart = null;
      selectedGhost = null;
      _ghostPreparation = null;
      _ghostSelectionGeneration++;
      error = e.message;
      ghostStartRejection = e.message;
      setupAction = null;
    } else if (e is RunStorageFailure || recorder.faulted) {
      storageFault = true;
      await _stopLocation();
      await _stopExtras();
      error = '기기 저장을 완료하지 못해 측정을 중단했어요. 다시 실행하면 마지막 저장 지점까지 복구돼요.';
      setupAction = null;
    } else {
      error = _message(e);
      setupAction = e is DeviceSetupException ? e.action : null;
    }
    _notify();
  }

  Future<void> openSettings() async {
    final action = setupAction;
    if (action == null) return;
    try {
      await location.openSettings(action);
    } on Object catch (e) {
      await _operationError(e);
    }
  }

  Future<void> _reloadLocal() async {
    final member = currentOwner;
    if (member == null) return;
    final loaded = await store.list(member, summaryOnly: true);
    final removed = await store.deletedIds(member);
    final deletions = await store.pendingDeletions(member);
    final ghostClosures = await store.pendingGhostClosures(member);
    if (currentOwner != member) return;
    deletedIds = {...deletedIds, ...removed};
    pendingDeleteCount = deletions.length;
    pendingGhostClosureCount = ghostClosures.length;
    remoteRecords.removeWhere((r) => removed.contains(r['id']));
    records = loaded
        .where(
          (r) =>
              !deletedIds.contains(r.id) &&
              r.phase == RunPhase.ended &&
              (r.summary?['metrics']?['distanceM'] as num? ??
                      RunCalculator.replay(r.inputs).distanceM) >
                  0,
        )
        .toList();
    final active = run;
    if (active?.phase == RunPhase.ended) {
      final refreshed = (await store.list(member, id: active!.id)).firstOrNull;
      if (currentOwner != member || deletedIds.contains(active.id)) return;
      if (refreshed != null) {
        active.result = refreshed.result;
        active.pending = refreshed.pending;
        active.syncState = refreshed.syncState;
        active.syncFailure = refreshed.syncFailure;
      }
    }
    _notify();
  }

  void clearResult() {
    if (recorder.active) return;
    recorder.current = null;
    recorder.calculator = RunCalculator();
    recorder.elapsedMs = 0;
    _notify();
  }

  Future<void> sync({bool manual = false}) async {
    if (_disposed ||
        syncing ||
        currentOwner == null ||
        preparing ||
        recorder.active ||
        (_syncDisabled && !manual)) {
      return;
    }
    if (!manual && _retryAt != null && _utcNow().isBefore(_retryAt!)) {
      return;
    }
    final member = currentOwner!;
    syncing = true;
    final done = _syncDone = Completer<void>();
    if (manual) {
      error = null;
      _syncDisabled = false;
    }
    _notify();
    try {
      await syncWorker.sync(member, retryBlocked: manual);
      if (currentOwner != member || _disposed) return;
      _networkFailures = 0;
      _retryAt = null;
      await _reloadLocal();
    } on ApiException catch (e) {
      if (currentOwner != member || _disposed) return;
      _networkFailures = (_networkFailures + 1).clamp(1, 6);
      _retryAt = _utcNow().add(
        Duration(seconds: (15 * (1 << (_networkFailures - 1))).clamp(15, 300)),
      );
      if (e.status == 401 || e.code == 'RUN_ACCOUNT_CHANGED') {
        _syncDisabled = true;
      }
      if (manual) error = e.message;
    } on Object catch (e) {
      if (currentOwner == member && !_disposed) {
        _retryAt = _utcNow().add(const Duration(seconds: 30));
        if (manual) error = _message(e);
      }
    } finally {
      syncing = false;
      if (!done.isCompleted) done.complete();
      if (identical(_syncDone, done)) _syncDone = null;
      try {
        if (!_disposed) await _reloadLocal();
      } on Object catch (e) {
        await _operationError(e);
      }
      _notify();
    }
  }

  /// [pageSize]를 비우면 서버 기본 개수로 받는다(MY I1은 기록을 끝까지 받아 50개씩 받는다).
  Future<void> loadHistory({bool more = false, int? pageSize}) async {
    if (_disposed ||
        loadingHistory ||
        currentOwner == null ||
        preparing ||
        recorder.active) {
      return;
    }
    if (more && nextCursor == null) return;
    final member = currentOwner!;
    loadingHistory = true;
    _notify();
    try {
      final page = await api.history(
        member,
        cursor: more ? nextCursor : null,
        size: pageSize,
      );
      if (currentOwner != member || _disposed) return;
      final items = (page['content'] as List)
          .map((r) => (r as Map).cast<String, dynamic>())
          .toList();
      historyNotice = null;
      final removed = await store.deletedIds(member);
      if (currentOwner != member || _disposed) return;
      final merged = more ? [...remoteRecords, ...items] : items;
      remoteRecords = {
        for (final r in merged)
          if (!removed.contains(r['id'])) r['id'] as String: r,
      }.values.toList();
      nextCursor = page['nextCursor'] as String?;
    } on Object catch (e) {
      if (currentOwner == member && !_disposed) historyNotice = _message(e);
    } finally {
      loadingHistory = false;
      _notify();
    }
  }

  Future<LocalRun?> localRecord(String id) async {
    final member = currentOwner;
    if (member == null || await owner() != member) {
      throw StateError('로그인 후 조회해 주세요.');
    }
    final record = (await store.list(member, id: id)).firstOrNull;
    if (currentOwner != member || await owner() != member) {
      throw StateError('계정이 변경되었어요.');
    }
    if ((await store.deletedIds(member)).contains(id)) {
      throw StateError('삭제한 기록이에요.');
    }
    return record;
  }

  Future<Map<String, dynamic>> detail(String id) async {
    final member = currentOwner;
    if (member == null) throw StateError('로그인 후 조회해 주세요.');
    if (deletedIds.contains(id)) throw StateError('삭제한 기록이에요.');
    if (preparing || recorder.active) {
      throw StateError('러닝 종료 후 서버 기록을 불러올 수 있어요.');
    }
    final result = await api.result(member, id);
    if (currentOwner != member || await owner() != member) {
      throw StateError('계정이 변경되었어요.');
    }
    if ((await store.deletedIds(member)).contains(id)) {
      throw StateError('삭제한 기록이에요.');
    }
    return result;
  }

  Future<void> deleteRecord(String id) async {
    final member = currentOwner;
    if (member == null || await owner() != member) {
      throw StateError('로그인 후 삭제해 주세요.');
    }
    await store.deleteRecord(member, id);
    if (currentOwner != member) return;
    deletedIds.add(id);
    records.removeWhere((r) => r.id == id);
    remoteRecords.removeWhere((r) => r['id'] == id);
    pendingDeleteCount = (await store.pendingDeletions(member)).length;
    if (run?.id == id && !recorder.active) clearResult();
    _notify();
    unawaited(sync(manual: true));
  }

  Future<void> saveVoiceSettings(RunVoiceSettings settings) async {
    final member = currentOwner;
    if (member == null) throw StateError('로그인 후 설정해 주세요.');
    await store.saveVoiceSettings(member, settings);
    if (currentOwner != member || _disposed) return;
    voiceSettings = settings;
    await audioGuide.configure(
      settings,
      id: run?.id,
      phase: run?.phase,
      metrics: run == null ? null : metrics,
    );
    _notify();
  }

  Future<void> testVoice() async {
    final member = currentOwner;
    if (member == null ||
        run?.phase == RunPhase.paused ||
        await owner() != member) {
      return;
    }
    await audioGuide.preview(
      () =>
          !_disposed && currentOwner == member && run?.phase != RunPhase.paused,
    );
  }

  Future<void> _sampleCadence({bool force = false}) async {
    if (device == null ||
        _deviceRunId == null ||
        !recorder.active ||
        run?.phase != RunPhase.running) {
      return;
    }
    final id = run!.id;
    final sample = await device!.sampleSteps(force: force);
    if (sample == null ||
        _disposed ||
        storageFault ||
        run?.id != id ||
        run?.phase != RunPhase.running) {
      return;
    }
    await recorder.cadence(
      (sample['steps'] as num).toInt(),
      (sample['durationMs'] as num).toInt(),
      sampleEndClockMs: (sample['sampleEndClockMs'] as num?)?.toInt(),
    );
    cadenceStatus = '측정 중';
  }

  Future<void> _samplePressure() async {
    if (!_pressureStarted ||
        _disposed ||
        storageFault ||
        run?.phase != RunPhase.running) {
      return;
    }
    final id = run!.id;
    try {
      final sample = await device?.samplePressure();
      if (sample == null ||
          _disposed ||
          storageFault ||
          run?.id != id ||
          run?.phase != RunPhase.running) {
        return;
      }
      await recorder.barometer(
        (sample['pressureHpa'] as num).toDouble(),
        (sample['pressureAccuracy'] as num).toInt(),
        sampleClockMs: (sample['sampleClockMs'] as num).toInt(),
      );
    } on RunStorageFailure {
      rethrow;
    } on Object {
      // Optional sensor failure never interrupts GPS or durable recording.
    }
  }

  Future<void> _refreshExtras() {
    if (_disposed) return Future.value();
    return _extrasJob ??= _updateExtras().whenComplete(() => _extrasJob = null);
  }

  Future<void> _updateExtras() async {
    try {
      final current = run;
      final running = !storageFault && current?.phase == RunPhase.running;
      if (!running) {
        if (_deviceRunId != null) await _stopExtras();
        if (current != null) {
          await audioGuide.update(current.id, current.phase, metrics);
        }
        return;
      }
      if (_deviceRunId != current!.id) {
        await _stopExtras();
        _deviceRunId = current.id;
        try {
          cadenceStatus = await device?.startSteps() ?? '센서 미지원';
        } on Object {
          cadenceStatus = '센서 연결 실패';
        }
        // Pressure does not depend on the presence of a step sensor.
        try {
          _pressureStarted = await device?.startPressure() ?? false;
        } on Object {
          _pressureStarted = false;
        }
      }
      if (run?.id != current.id ||
          run?.phase != RunPhase.running ||
          _disposed) {
        await _stopExtras();
        return;
      }
      if (device != null &&
          _ticks % 5 == 0 &&
          !await device!.permissionGranted()) {
        error = '신체 활동 권한이 해제되어 마지막 기록까지 저장했어요.';
        setupAction = DeviceSettingsAction.appSettings;
        await recorder.end(reason: 'PERMISSION_REVOKED');
        await _stopLocation();
        await _stopExtras();
        await _reloadLocal();
        _notify();
        return;
      }
      await _samplePressure();
      try {
        await _sampleCadence();
      } on RunStorageFailure {
        rethrow;
      } on Object {
        cadenceStatus = '센서 연결 실패';
      }
      if (run?.id != current.id ||
          run?.phase != RunPhase.running ||
          _disposed) {
        return;
      }
      await audioGuide.update(current.id, current.phase, metrics);
    } on Object catch (e) {
      if (e is RunStorageFailure) {
        await _operationError(e);
      } else {
        cadenceStatus = '센서 연결 실패';
        _notify();
      }
    } finally {
      if (!_disposed &&
          _deviceRunId != null &&
          run?.phase != RunPhase.running) {
        await _stopExtras();
      }
    }
  }

  Future<void> _stopExtras() async {
    _deviceRunId = null;
    _pressureStarted = false;
    try {
      await device?.stopPressure();
    } on Object {
      /* Optional pressure sensor failure must not interrupt recording. */
    }
    if (run?.phase == RunPhase.paused) cadenceStatus = '일시정지';
    if (run?.phase == RunPhase.ended) {
      cadenceStatus = metrics.averageCadence == null ? '측정 없음' : '측정 완료';
    }
    try {
      await device?.stopSteps();
    } on Object {
      /* Recording remains durable. */
    }
    try {
      await audioGuide.stop();
    } on Object {
      /* Missing audio never stops recording. */
    }
  }

  Future<void> _stopLocation({int? expectedToken}) async {
    if (expectedToken != null && expectedToken != _locationGeneration) return;
    ++_locationGeneration;
    final subscription = _gps;
    _gps = null;
    await subscription?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        countdown != null &&
        canCancelStart &&
        !recorder.active) {
      cancelStart();
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(bindOwner());
      if (hasPendingGhostStart) unawaited(retryGhostStart());
      if (!_syncDisabled) unawaited(sync());
    }
  }

  static String _message(Object e) => e is ApiException
      ? e.message
      : e.toString().replaceFirst('Bad state: ', '');
  Future<void> shutdown() => _shutdown ??= _close();

  Future<void> _close() async {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    await _stopWatchingStart();
    await _stopLocation();
    await _extrasJob;
    await _stopExtras();
    await audioGuide.close();
    await device?.close();
    await _changes.cancel();
    await recorder.close();
    await store.close();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
