import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/recording_models.dart';
import 'package:wadadak/features/run/presentation/course_start_view.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';

import 'run_controller_test.dart' show FailingStore, TestApi, TestLocation, until;

/// 코스 러닝 서버 연결(F6, 정책 D-08·RCR-01): 준비 → 측정 전(출발점 안내) → 반경 안에서 카운트다운 → 시작 신호 → 측정.
/// 연결이 안 되면 시작하지 않는다.
class CourseApi extends TestApi {
  final prepared = <(String owner, String id, String courseId)>[];
  final started = <(String owner, String id, DateTime startedAt)>[];
  Object? prepareError, startError;

  /// 출발점 위도. 테스트 위치는 (36, 127)에서 시작한다
  double startLat = 36;

  @override
  Future<Map<String, dynamic>> prepareCourse(String owner, String id, String courseId) async {
    if (prepareError != null) throw prepareError!;
    prepared.add((owner, id, courseId));
    return {
      'sessionId': id,
      'courseId': courseId,
      'name': '테스트 코스',
      'route': [
        {'lat': startLat, 'lng': 127.0},
        {'lat': startLat + .01, 'lng': 127.0},
      ],
      'totalDistanceMeters': 1112,
      'version': 0,
    };
  }

  @override
  Future<void> startCourse(String owner, String id, DateTime startedAt) async {
    if (startError != null) throw startError!;
    started.add((owner, id, startedAt));
  }

  final segmentEnds = <String>[];
  @override
  Future<void> segmentEnd(String owner, String id) async => segmentEnds.add(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RunController controller;
  late TestLocation location;
  late CourseApi api;

  setUp(() {
    sqfliteFfiInit();
    location = TestLocation();
    api = CourseApi();
    controller = RunController(
      FailingStore(),
      location,
      api,
      () async => 'alice',
      wait: (_) async {},
      utcNow: () => location.utc,
      nowMs: location.nowMs,
      lifecycleState: () => AppLifecycleState.resumed,
      automaticTicks: false,
    );
  });
  tearDown(() async {
    await until(() => !controller.syncing && !controller.loadingHistory);
    await controller.shutdown();
    controller.dispose();
    for (final stream in location.streams) {
      await stream.close();
    }
  });

  Future<void> openCourse() async {
    controller.selectCourse(const CourseSelection('course-1', '테스트 코스'));
    await controller.prepareStart();
  }

  test('preparing a course stops before measuring and shows the way to the start point', () async {
    await openCourse();

    final start = controller.courseStart!;
    expect(controller.recorder.active, false);
    expect(api.prepared.single, ('alice', start.runId, 'course-1'));
    expect(api.started, isEmpty);
    expect(start.start, const GeoPoint(36, 127));
    expect(start.nearStart, true);
  });

  test('at the start point it starts with the same session id and start time as the record', () async {
    await openCourse();
    final runId = controller.courseStart!.runId;
    await controller.prepareStart();

    final run = controller.run!;
    expect(controller.recorder.active, true);
    expect(run.id, runId);
    expect(api.prepared, hasLength(1));
    expect(api.started.single.$2, run.id);
    // 업로드 준비가 서버 코스 시도와 맞으려면 시작 신호의 startedAt이 기록과 같아야 한다
    expect(api.started.single.$3, run.startedAt);
    expect(controller.courseRunId, run.id);
    expect(controller.course?.name, '테스트 코스');
    expect(controller.courseTracker?.route.route.first, const GeoPoint(36, 127)); // 준비 응답 경로로 진행도를 따라간다
    expect(controller.courseStart, isNull);
    expect(controller.selectedCourse, isNull);
  });

  test('cannot start outside the start radius and can after reaching it', () async {
    api.startLat = 36.001; // 약 111 m 북쪽
    await openCourse();
    expect(controller.courseStart!.nearStart, false);

    await controller.prepareStart();
    expect(controller.recorder.active, false);
    expect(api.started, isEmpty);

    location.streams.last.add(location.point(36.00095)); // 출발점까지 약 6 m
    await until(() => controller.courseStart!.nearStart);
    await controller.prepareStart();

    expect(controller.recorder.active, true);
    expect(api.started, hasLength(1));
  });

  test('free run does not call course APIs', () async {
    await controller.prepareStart();

    expect(controller.recorder.active, true);
    expect(api.prepared, isEmpty);
    expect(api.started, isEmpty);
    expect(controller.courseRunId, isNull);
  });

  test('offline start signal does not start the run and keeps the start point open', () async {
    api.startError = const ApiException(ApiException.network, 'offline');
    await openCourse();
    await controller.prepareStart();

    expect(controller.recorder.active, false);
    expect(controller.error, contains('인터넷'));
    expect(controller.courseStart, isNotNull); // 다시 시도할 수 있게 남긴다
  });

  test('unavailable course does not open the start point and shows the server message', () async {
    api.prepareError = const ApiException('COURSE-002', '비공개되었거나 삭제된 코스입니다.', status: 409);
    await openCourse();

    expect(controller.courseStart, isNull);
    expect(api.started, isEmpty);
    expect(controller.error, '비공개되었거나 삭제된 코스입니다.');
    expect(controller.selectedCourse?.courseId, 'course-1');
  });

  test('leaving the start point stops watching the location and keeps the course', () async {
    await openCourse();
    final approach = location.streams.last;
    controller.cancelCourseStart();

    expect(controller.courseStart, isNull);
    expect(controller.selectedCourse?.courseId, 'course-1');
    await until(() => !approach.hasListener);
    expect(api.started, isEmpty);
  });

  test('course cannot be changed while a run is active', () async {
    await controller.prepareStart();
    controller.selectCourse(const CourseSelection('course-1', '테스트 코스'));

    expect(controller.selectedCourse, isNull);
  });

  Future<void> startCourse() async {
    await openCourse();
    await controller.prepareStart();
  }

  RunInput? segmentEnd() => controller.run!.inputs.where((i) => i.kind == RunKind.segmentEnd).firstOrNull;

  test('reaching the end of the route ends the course segment and keeps recording as a free run (RUN-08)', () async {
    await startCourse();
    final runId = controller.run!.id;
    location.clock += 2000;
    location.streams.last.add(location.point(36.00995)); // 끝까지 약 6 m

    await until(() => segmentEnd() != null);
    expect(segmentEnd()!.reason, 'ROUTE_END');
    expect(controller.courseEndReason, 'ROUTE_END');
    expect(controller.onCourse, false);
    expect(controller.recorder.active, true); // 세션은 자유 러닝으로 계속
    await until(() => api.segmentEnds.isNotEmpty);
    expect(api.segmentEnds.single, runId);

    location.clock += 2000;
    location.streams.last.add(location.point(36.0101));
    await until(() => controller.run!.inputs.where((i) => i.kind == RunKind.gps).length >= 3);
    expect(controller.run!.inputs.where((i) => i.kind == RunKind.segmentEnd), hasLength(1));
  });

  test('the start point is not the end even when standing still', () async {
    await startCourse();
    location.clock += 2000;
    location.streams.last.add(location.point(36));
    await until(() => controller.run!.inputs.where((i) => i.kind == RunKind.gps).length >= 2);

    expect(segmentEnd(), isNull);
    expect(controller.onCourse, true);
  });

  test('ending only the course keeps the run paused and records COURSE_ONLY (RUN-07)', () async {
    await startCourse();
    await controller.pause();
    await controller.endCourse('COURSE_ONLY');

    expect(segmentEnd()!.reason, 'COURSE_ONLY');
    expect(controller.run!.phase, RunPhase.paused);
    expect(controller.onCourse, false);
    await until(() => api.segmentEnds.isNotEmpty);

    await controller.endCourse('COURSE_ONLY'); // 두 번 눌러도 한 번만
    expect(controller.run!.inputs.where((i) => i.kind == RunKind.segmentEnd), hasLength(1));
  });

  test('a free run has no course segment to end', () async {
    await controller.prepareStart();
    await controller.endCourse('COURSE_ONLY');

    expect(segmentEnd(), isNull);
    expect(api.segmentEnds, isEmpty);
  });

  test('running off the course raises the deviation alert and confirm closes it (7.1·7.2)', () async {
    await startCourse();
    var gps = 1;
    Future<void> move(double eastM) async {
      location.clock += 2000;
      location.streams.last.add(Position(
        latitude: 36.0001,
        longitude: 127 + eastM / 90063, // 위도 36°에서 경도 1° ≈ 90 km
        timestamp: location.utc,
        accuracy: 3,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ));
      gps++;
      await until(() => controller.run!.inputs.where((i) => i.kind == RunKind.gps).length >= gps);
    }

    for (var east = 5.0; east <= 40; east += 5) {
      await move(east); // 2초에 5 m씩 동쪽으로
    }
    expect(controller.deviationAlert, false); // 후보만
    for (var i = 0; i < 6; i++) {
      await move(40);
    }

    expect(controller.deviationAlert, true);
    expect(controller.routeGuidance!.distanceM, closeTo(40, 1));
    controller.acknowledgeDeviation();
    expect(controller.deviationAlert, false);
    expect(controller.recorder.active, true); // 안내 중에도 측정은 계속
  });

  test('deviation alerts stop once the course segment ends', () async {
    await startCourse();
    await controller.pause();
    await controller.endCourse('COURSE_ONLY');

    expect(controller.deviationAlert, false);
  });

  test('arrival voice tells the course time and pace measured on the device (AUD-06)', () {
    expect(
      RunController.courseArrivalVoice(1627000, 5000),
      '코스 끝에 도착했어요. 걸린 시간 27분 7초, 평균 페이스 5분 25초입니다. 자유 러닝으로 이어서 기록해요.',
    );
  });

  testWidgets('start point view turns the start button on only inside the radius', (tester) async {
    Future<void> show(GeoPoint position) => tester.pumpWidget(
      ProviderScope(
        overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
        child: MaterialApp(
          home: CourseStartView(
            start: CourseStart(
              'run-1',
              const CourseSelection('course-1', '한강 야경 5K'),
              const CourseSnapshot(route: [GeoPoint(36, 127), GeoPoint(36.01, 127)], totalDistanceMeters: 1112),
              position,
            ),
            onStart: () {},
            onCancel: () {},
          ),
        ),
      ),
    );

    await show(const GeoPoint(35.999, 127));
    expect(find.text('출발점까지 111 m'), findsOneWidget);
    expect(find.text('한강 야경 5K'), findsOneWidget);
    expect(tester.widget<RunHoldToStart>(find.byType(RunHoldToStart)).onStart, isNull);

    await show(const GeoPoint(36.0001, 127));
    expect(find.text('출발점이에요'), findsOneWidget);
    expect(tester.widget<RunHoldToStart>(find.byType(RunHoldToStart)).onStart, isNotNull);
  });
}
