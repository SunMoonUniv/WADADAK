import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
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
