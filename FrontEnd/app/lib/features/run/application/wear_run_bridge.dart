import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/course_api_client.dart';
import '../../../core/map/geo_point.dart';
import '../../home/my_location.dart';
import '../data/own_ghost_api.dart';
import '../domain/course_run.dart';
import '../domain/own_ghost.dart';
import '../domain/recording_models.dart';
import '../domain/route_guidance.dart';
import 'own_ghost_controller.dart';
import 'run_controller.dart';

final wearRunBridgeProvider = Provider<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final bridge = WearRunBridge(
    () => ref.read(runControllerProvider),
    loadCourses: () async {
      final api = ref.read(courseApiClientProvider);
      final saved = await api.bookmarks();
      final courses = [
        for (final course in saved.courses)
          if (!course.pendingDelete) course.card,
      ];
      if (courses.isNotEmpty) return courses;
      final here = await ref.read(myLocationProvider).ifAllowed();
      if (here == null) return const [];
      const delta = .03;
      final nearby = await api.listCourses(
        southWest: GeoPoint(here.lat - delta, here.lng - delta),
        northEast: GeoPoint(here.lat + delta, here.lng + delta),
        origin: here,
        sort: CourseListSort.nearest,
      );
      return nearby.courses;
    },
  );
  const channel = MethodChannel('com.wadadak.app/wear_run');
  channel.setMethodCallHandler(bridge.handle);
  ref.onDispose(() {
    channel.setMethodCallHandler(null);
    bridge.dispose();
  });
});

/// The handset is the sole writer. Every control after start targets a session ID.
class WearRunBridge {
  WearRunBridge(this._controller, {this.loadCourses});

  final RunController Function() _controller;
  String? _operation;
  String? _startFailure;
  final Future<List<CourseListItem>> Function()? loadCourses;
  String? _catalogOwner;
  List<CourseListItem> _courses = const [];
  CourseListItem? _courseCard;
  CourseSelection? _watchCourse;
  OwnGhostController? _ghosts;

  void dispose() {
    _ghosts?.dispose();
    _ghosts = null;
  }

  void _resetCatalog(String? owner) {
    if (_catalogOwner == owner) return;
    dispose();
    _catalogOwner = owner;
    _courses = const [];
    _courseCard = null;
    _watchCourse = null;
  }

  Future<Map<String, Object?>> handle(MethodCall call) async {
    if (call.method != 'request') throw MissingPluginException();
    final args = call.arguments;
    if (args is! Map || args['command'] is! String) {
      throw PlatformException(code: 'invalid_request');
    }
    final command = args['command'] as String;
    final controller = _controller();
    final owner = await controller.owner();
    _resetCatalog(owner);
    if (owner == null) {
      return {'phase': 'unavailable', 'message': '폰에서 로그인해 주세요.'};
    }
    if (owner != controller.currentOwner) await controller.bindOwner();
    if (owner != controller.currentOwner || owner != await controller.owner()) {
      return {'phase': 'unavailable', 'message': '폰의 계정을 확인해 주세요.'};
    }
    if (command == 'status') return _status(controller, owner, args);

    final mode = args['mode'] as String?;
    final selectionId = args['sessionId'] as String?;
    if (const {
      'courses',
      'selectCourse',
      'selectGhost',
      'prepareCourse',
      'cancelCourse',
    }.contains(command)) {
      return _courseAction(controller, owner, command, mode, selectionId);
    }

    final run = controller.run;
    if (command == 'start') {
      final readyId = args['readyId'];
      if (readyId is String) {
        controller.startFromWear(readyId);
        return _snapshot(controller);
      }
      if (_operation != null || controller.preparing) {
        return _snapshot(controller);
      }
      final approach = controller.courseStart;
      final courseStart =
          approach != null &&
          approach.runId == selectionId &&
          approach.nearStart &&
          (mode == 'course' || mode == 'ghost');
      if (controller.recorder.active ||
          (controller.hasOtherRunPreparation && !courseStart)) {
        return _snapshot(controller, '폰에서 진행 중인 러닝이나 준비를 확인해 주세요.');
      }
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return _snapshot(
          controller,
          courseStart ? '폰의 와다닥을 연 상태에서 시작해 주세요.' : '폰에서 ‘워치로 시작 준비’를 눌러 주세요.',
        );
      }
      _operation = 'start';
      _startFailure = null;
      unawaited(
        _start(controller, freeOnly: !courseStart, wearCourse: courseStart),
      );
      return _snapshot(controller);
    }
    if (command == 'cancelStart') {
      if ((_operation == 'start' || controller.wearStarting) &&
          controller.canCancelStart) {
        controller.cancelStart();
      }
      return _snapshot(controller);
    }
    if (command == 'openSettings') {
      if (!controller.recorder.active && !controller.preparing) {
        await controller.openSettings();
      }
      return _snapshot(controller);
    }
    if (!const {
      'pause',
      'resume',
      'end',
      'ackDeviation',
      'muteDeviation',
    }.contains(command)) {
      throw PlatformException(code: 'invalid_command');
    }
    if (run == null || selectionId != run.id) {
      return _snapshot(controller, '폰의 현재 러닝을 다시 확인해 주세요.');
    }
    if (_operation != null || run.phase == RunPhase.ended) {
      return _snapshot(controller);
    }
    _operation = command;
    try {
      switch (command) {
        case 'pause':
          if (run.phase == RunPhase.running) await controller.pause();
        case 'resume':
          if (run.phase == RunPhase.paused) await controller.resume();
        case 'end':
          if (run.phase == RunPhase.paused) await controller.end();
        case 'ackDeviation':
          if (controller.onCourse) controller.acknowledgeDeviation();
        case 'muteDeviation':
          if (controller.onCourse) controller.muteDeviation();
      }
    } finally {
      _operation = null;
    }
    if (owner != await controller.owner()) {
      return {'phase': 'unavailable', 'message': '폰의 계정을 확인해 주세요.'};
    }
    return _snapshot(controller);
  }

  Future<Map<String, Object?>> _courseAction(
    RunController controller,
    String owner,
    String command,
    String? mode,
    String? id,
  ) async {
    if (_operation != null ||
        controller.preparing ||
        controller.recorder.active) {
      return _snapshot(controller, '진행 중인 러닝을 먼저 확인해 주세요.');
    }
    _operation = command;
    String? notice;
    try {
      switch (command) {
        case 'courses':
          final courses = await loadCourses?.call() ?? const <CourseListItem>[];
          if (await controller.owner() != owner) break;
          _courses = courses.take(10).toList(growable: false);
        case 'selectCourse':
          final selected = _courses
              .where((item) => item.courseId == id)
              .firstOrNull;
          if (selected == null || (mode != 'course' && mode != 'ghost')) {
            throw StateError('코스를 다시 골라 주세요.');
          }
          if (controller.courseStart != null ||
              controller.selectedFreeGhost != null) {
            throw StateError('폰에 있는 러닝 준비를 먼저 확인해 주세요.');
          }
          if (controller.run?.phase == RunPhase.ended) controller.clearResult();
          final selection = CourseSelection(selected.courseId, selected.name);
          controller.selectCourse(selection);
          if (!identical(controller.selectedCourse, selection)) {
            throw StateError('코스를 선택할 수 없는 상태예요.');
          }
          _courseCard = selected;
          _watchCourse = selection;
          dispose();
          if (mode == 'ghost') {
            final context = await controller.prepareGhostSelection();
            if (context.owner != owner) break;
            final snapshot = context.snapshot;
            final choices = OwnGhostController(
              OwnGhostApi(controller.api),
              owner: owner,
              course: GhostCourseContext(snapshot.courseId!, snapshot.version!),
            );
            _ghosts = choices;
            await choices.load(sort: OwnGhostSort.best);
            if (choices.error != null) notice = choices.error;
          }
        case 'selectGhost':
          final choices = _ghosts;
          if (choices == null ||
              choices.owner != owner ||
              !identical(controller.selectedCourse, _watchCourse)) {
            throw StateError('코스와 고스트를 다시 골라 주세요.');
          }
          final candidate = [
            ?choices.summary.best,
            ...choices.candidates,
          ].where((item) => item.id == id).firstOrNull;
          if (candidate == null) throw StateError('고스트 기록을 다시 골라 주세요.');
          await choices.select(candidate);
          if (await controller.owner() != owner ||
              !identical(controller.selectedCourse, _watchCourse)) {
            break;
          }
          final prepared = choices.prepared;
          if (prepared == null) {
            throw StateError(choices.error ?? '이 기록으로는 고스트 대결을 시작할 수 없어요.');
          }
          controller.selectGhost(prepared);
          if (!identical(controller.selectedGhost, prepared)) {
            throw StateError('고스트를 선택할 수 없는 상태예요.');
          }
          _watchCourse = controller.selectedCourse;
        case 'prepareCourse':
          if (_watchCourse == null ||
              !identical(controller.selectedCourse, _watchCourse) ||
              (mode == 'ghost' && controller.selectedGhost == null)) {
            throw StateError('코스와 고스트를 확인해 주세요.');
          }
          if (WidgetsBinding.instance.lifecycleState !=
              AppLifecycleState.resumed) {
            throw StateError('폰에서 와다닥을 연 뒤 출발점 지도를 열어 주세요.');
          }
          _operation = 'start';
          _startFailure = null;
          unawaited(_start(controller, freeOnly: false));
          return _snapshot(controller);
        case 'cancelCourse':
          if (controller.courseStart != null &&
              identical(controller.selectedCourse, _watchCourse)) {
            controller.cancelCourseStart();
          } else if (identical(controller.selectedCourse, _watchCourse)) {
            controller.clearCourse();
            _watchCourse = null;
            _courseCard = null;
            dispose();
          }
      }
    } on ApiException catch (error) {
      notice = error.code == ApiException.network
          ? '인터넷에 연결되지 않았어요. 연결을 확인해 주세요.'
          : error.message;
    } on StateError catch (error) {
      notice = error.message.toString();
    } on Object {
      notice = '폰에서 코스와 연결 상태를 확인해 주세요.';
    } finally {
      if (_operation != 'start') _operation = null;
    }
    if (await controller.owner() != owner) {
      _resetCatalog(null);
      return {'phase': 'unavailable', 'message': '폰의 계정을 확인해 주세요.'};
    }
    return _snapshot(controller, notice);
  }

  Future<void> _start(
    RunController controller, {
    required bool freeOnly,
    bool wearCourse = false,
  }) async {
    try {
      await controller.prepareStart(freeOnly: freeOnly, wearCourse: wearCourse);
    } on Object {
      _startFailure = '폰에서 러닝 시작 상태를 확인해 주세요.';
    } finally {
      _operation = null;
    }
  }

  Future<Map<String, Object?>> _status(
    RunController controller,
    String owner,
    Map<dynamic, dynamic> args,
  ) async {
    final snapshot = _snapshot(controller);
    final sessionId = args['sessionId'];
    if (snapshot['phase'] != 'ready' ||
        controller.wearReadyId != null ||
        sessionId is! String ||
        sessionId.isEmpty) {
      return snapshot;
    }

    // A phone result can be dismissed while the watch is out of range.
    // Look up only the exact session the watch saw, under the current owner.
    final saved =
        controller.records.where((run) => run.id == sessionId).firstOrNull ??
        (await controller.store.list(owner, summaryOnly: true, id: sessionId))
            .firstOrNull;
    if (controller.currentOwner != owner || await controller.owner() != owner) {
      return {'phase': 'unavailable', 'message': '폰의 계정을 확인해 주세요.'};
    }
    final latest = _snapshot(controller);
    if (saved == null ||
        controller.deletedIds.contains(sessionId) ||
        latest['phase'] != 'ready' ||
        controller.wearReadyId != null) {
      return latest;
    }
    return _snapshot(controller, null, saved, args['mode'] as String?);
  }

  Map<String, Object?> _snapshot(
    RunController controller, [
    String? message,
    LocalRun? recovered,
    String? rememberedMode,
  ]) {
    final run = recovered ?? controller.run;
    final approach = controller.courseStart;
    final selected = controller.selectedCourse;
    final ghost = controller.selectedGhost;
    final readyForWatch = controller.wearReadyId != null;
    final active =
        run != null &&
        (recovered != null || run.phase != RunPhase.ended || selected == null);
    final phase = controller.storageFault
        ? 'unavailable'
        : readyForWatch
        ? 'ready'
        : _operation == 'start' || controller.preparing
        ? 'preparing'
        : _operation == 'end'
        ? 'ending'
        : approach != null
        ? 'approach'
        : active
        ? run.phase.name
        : 'ready';
    final courseResult = phase == 'ended'
        ? (run?.result?['course'] ?? run?.summary?['course']) as Map?
        : null;
    final ghostResult = phase == 'ended'
        ? (run?.result?['ghost'] ?? run?.summary?['ghost']) as Map?
        : null;
    final mode = switch ((
      ghostResult != null || active && run.ghost != null,
      courseResult != null || active && controller.courseRunId == run.id,
    )) {
      (true, _) => 'ghost',
      (_, true) => 'course',
      _ when recovered != null => switch (rememberedMode) {
        'ghost' => 'ghost',
        'course' => 'course',
        _ => 'free',
      },
      _ when ghost != null => 'ghost',
      _ when selected != null => 'course',
      _ => 'free',
    };
    final card = selected?.courseId == _courseCard?.courseId
        ? _courseCard
        : null;
    final choices = _ghosts;
    final candidates = <String, OwnGhostCandidate>{
      if (choices != null) ...{
        for (final item in choices.candidates) item.id: item,
      },
    };
    final best = choices?.summary.best;
    if (best != null) candidates[best.id] = best;
    final metrics = controller.metrics;
    final savedMetrics = recovered?.summary?['metrics'] as Map?;
    final distance =
        (savedMetrics?['distanceM'] as num?)?.toDouble() ?? metrics.distanceM;
    final activeMs =
        (savedMetrics?['activeMs'] as num?)?.toInt() ?? metrics.activeMs;
    final pace = recovered == null
        ? metrics.paceSecondsPerKm
        : (savedMetrics?['paceSecondsPerKm'] as num?)?.toDouble();
    final tracker = controller.onCourse ? controller.courseTracker : null;
    final guidance = tracker == null ? null : controller.routeGuidance;
    final comparison = controller.ghostComparison;
    final error = message ?? controller.error ?? _startFailure;
    final route = approach?.snapshot.routeSegments ?? tracker?.route.segments;
    final lastGps = tracker?.points.lastOrNull?.input;
    final position =
        approach?.position ??
        (lastGps?.lat != null && lastGps?.lng != null
            ? GeoPoint(lastGps!.lat!, lastGps.lng!)
            : null);
    final continuing = active && controller.courseEndReason != null;

    return {
      'phase': phase,
      'sessionId': approach?.runId ?? run?.id,
      'readyId': controller.wearReadyId,
      'mode': mode,
      'courseName': courseResult?['courseName'] ??
          (recovered == null
              ? approach?.course?.name ?? selected?.name ?? controller.course?.name
              : null),
      'courseDistanceM':
          card?.distanceMeters ?? approach?.snapshot.totalDistanceMeters,
      'ghostSeconds': ghost?.seconds ?? run?.ghost?.intent.sourceSeconds,
      'onCourse': controller.onCourse,
      'continuing': continuing,
      'courseEndReason': continuing ? controller.courseEndReason : null,
      'setupIssue': controller.setupAction != null && phase == 'ready'
          ? 'permissions'
          : error?.contains('인터넷에 연결되지') == true
          ? 'offline'
          : null,
      'gpsWeak': controller.gpsNotice != null && phase == 'running',
      'deviation': controller.deviationAlert,
      'offRoute':
          guidance?.state == GuidanceState.off && guidance?.uncertain == false,
      'remainingM': tracker == null
          ? null
          : tracker.route.length - (tracker.positionM ?? 0),
      'ghostDistanceM': comparison?.distanceM,
      'ghostTimeDeltaMs': comparison?.timeDeltaMs,
      if (comparison?.position case final ghostPosition?)
        'ghostPosition': [ghostPosition.lat, ghostPosition.lng],
      if (courseResult != null)
        'courseResult': {
          'completed': courseResult['completed'] == true,
          'recognizedDistanceM': courseResult['recognizedDistanceMeters'],
          'seconds': courseResult['courseElapsedSeconds'],
          'name': courseResult['courseName'],
        },
      if (ghostResult != null)
        'ghostResult': {
          'outcome': ghostResult['outcome'],
          'ours': ghostResult['courseElapsedSeconds'],
          'theirs': ghostResult['sourceElapsedSeconds'],
        },
      'courses': [
        for (final item in _courses)
          {
            'id': item.courseId,
            'name': item.name,
            'distanceM': item.distanceMeters,
          },
      ],
      'ghosts': [
        for (final item in [
          ?best,
          ...candidates.values.where((c) => c.id != best?.id),
        ].take(10))
          {
            'id': item.id,
            'name': item.id == best?.id ? '내 최고 기록' : '내 완주 기록',
            'seconds': item.seconds,
            'distanceM': item.distanceM,
          },
      ],
      if (approach != null) ...{
        'nearStart': approach.nearStart,
        'startDistanceM': approach.distanceToStartM,
      },
      if (position != null) 'position': [position.lat, position.lng],
      if (route != null)
        'route': [
          for (final segment in route.take(12))
            [
              for (
                var i = 0;
                i < segment.length;
                i += (segment.length / 40).ceil().clamp(1, 100000).toInt()
              )
                [segment[i].lat, segment[i].lng],
              if (segment.length > 1) [segment.last.lat, segment.last.lng],
            ],
        ],
      'countdown': controller.countdown,
      'countdownStepRemainingMs': controller.countdownStepRemainingMs,
      'canCancel':
          (_operation == 'start' || controller.wearStarting) &&
          controller.canCancelStart,
      'distanceM': distance,
      'activeMs': activeMs,
      'pace':
          pace != null &&
              pace.isFinite &&
              (distance >= 25 || phase == 'ended')
          ? pace
          : null,
      'message':
          message ??
          (phase == 'running'
              ? controller.gpsNotice
              : controller.error ?? _startFailure),
      'saved':
          phase == 'ended' &&
          (recovered != null
              ? distance > 0
              : controller.records.any((item) => item.id == run?.id)),
    };
  }
}
