import 'dart:async';

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
import '../../../core/permissions/device_setup.dart';
import '../../../core/time/monotonic_clock.dart';
import '../domain/run_location_policy.dart';
import '../data/run_audio_output.dart';
import 'audio_guide.dart';
import '../data/run_device.dart';
import '../domain/run_voice.dart';
import '../domain/recording_models.dart';
import 'run_recorder.dart';
import 'run_sync_worker.dart';

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
  }) : audioGuide = audio ?? AudioGuide(RunAudioOutput()),
       _wait = wait ?? Future<void>.delayed,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _lifecycleState =
           lifecycleState ?? (() => WidgetsBinding.instance.lifecycleState) {
    audioGuide.onChanged = _notify;
    recorder = RunRecorder(store, nowMs ?? MonotonicClock().nowMs);
    syncWorker = RunSyncWorker(
      api,
      store,
      owner,
      canSync: () => !preparing && !recorder.active && !_disposed,
    );
    _changes = recorder.changes.stream.listen((_) {
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
  String? _deviceRunId;
  Completer<void>? _syncDone;
  Future<void>? _extrasJob;
  final RunApiClient api;
  final Future<String?> Function() owner;
  late final RunRecorder recorder;
  late final RunSyncWorker syncWorker;
  Timer? _timer;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _utcNow;
  final AppLifecycleState? Function() _lifecycleState;
  late final StreamSubscription<void> _changes;
  StreamSubscription<Position>? _gps;
  List<LocalRun> records = [];
  List<Map<String, dynamic>> remoteRecords = [];
  String? currentOwner, error, gpsNotice, nextCursor, historyNotice;
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
        cancelStart();
        currentOwner = null;
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
        voiceSettings = const RunVoiceSettings();
        if (member == null) return;
        voiceSettings = await store.voiceSettings(member);
        audioGuide.restoreSettings(voiceSettings);
        deletedIds = await store.deletedIds(member);
        pendingDeleteCount = (await store.pendingDeletions(member)).length;
        records = (await recorder.recover(member))
            .where((r) => RunCalculator.replay(r.inputs).distanceM > 0)
            .toList();
        if (await owner() != member) {
          records = [];
          continue;
        }
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

  Future<void> prepareStart() async {
    if (preparing || recorder.active || storageFault || _disposed) return;
    await bindOwner();
    if (preparing || recorder.active || storageFault || _disposed) return;
    final member = await owner();
    if (member == null) {
      error = '로그인 후 시작해 주세요.';
      _notify();
      return;
    }
    final generation = ++_generation;
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
      _latest = position;
      _lastFixAt = _utcNow();
      _gapOpen = false;
      locationToken = _startLocation();
      for (var value = 3; value > 0; value--) {
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
      _committing = true;
      countdown = null;
      _notify();
      await recorder.start(const Uuid().v7(), member, _utcNow());
      currentOwner = member;
      if (_disposed || await owner() != member) {
        await recorder.end(reason: 'ACCOUNT_CHANGED');
        await bindOwner();
        return;
      }
      await _refreshExtras();
      final latest = _latest!;
      await recorder.gps(
        latest.latitude,
        latest.longitude,
        latest.accuracy,
        measuredAt: latest.timestamp,
        speedMps: latest.speed,
        speedAccuracyMps: latest.speedAccuracy,
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
      _notify();
    }
  }

  void cancelStart() {
    if (recorder.active || _committing) return;
    ++_generation;
    countdown = null;
    preparing = false;
    unawaited(_stopLocation());
    _notify();
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
          !_syncDisabled &&
          !syncing &&
          (pendingDeleteCount > 0 ||
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
    if (e is RunStorageFailure || recorder.faulted) {
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
    final loaded = await store.list(member);
    final removed = await store.deletedIds(member);
    final deletions = await store.pendingDeletions(member);
    if (currentOwner != member) return;
    deletedIds = {...deletedIds, ...removed};
    pendingDeleteCount = deletions.length;
    remoteRecords.removeWhere((r) => removed.contains(r['id']));
    records = loaded
        .where(
          (r) =>
              !deletedIds.contains(r.id) &&
              r.phase == RunPhase.ended &&
              RunCalculator.replay(r.inputs).distanceM > 0,
        )
        .toList();
    final active = run;
    if (active?.phase == RunPhase.ended) {
      final refreshed = records.where((r) => r.id == active!.id).firstOrNull;
      if (refreshed != null) {
        active!.result = refreshed.result;
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

  Future<void> loadHistory({bool more = false}) async {
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
      final page = await api.history(member, cursor: more ? nextCursor : null);
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
        cadenceStatus = await device?.startSteps() ?? '센서 미지원';
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
      await _sampleCadence();
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
