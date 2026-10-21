import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/course_run.dart';

import 'run_controller_test.dart' show FailingStore, TestApi, TestLocation, until;

/// 코스 러닝 서버 연결(F6, 정책 D-08): 준비 → 카운트다운 → 시작 신호 → 측정. 연결이 안 되면 시작하지 않는다.
class CourseApi extends TestApi {
  final prepared = <(String owner, String id, String courseId)>[];
  final started = <(String owner, String id, DateTime startedAt)>[];
  Object? prepareError, startError;

  @override
  Future<Map<String, dynamic>> prepareCourse(String owner, String id, String courseId) async {
    if (prepareError != null) throw prepareError!;
    prepared.add((owner, id, courseId));
    return {'sessionId': id, 'courseId': courseId, 'name': '테스트 코스', 'route': [], 'totalDistanceMeters': 1000, 'version': 0};
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

  test('selected course is prepared and started with the same session id and start time as the record', () async {
    controller.selectCourse(const CourseSelection('course-1', '테스트 코스'));
    await controller.prepareStart();

    final run = controller.run!;
    expect(controller.recorder.active, true);
    expect(api.prepared.single, ('alice', run.id, 'course-1'));
    expect(api.started.single.$2, run.id);
    // 업로드 준비가 서버 코스 시도와 맞으려면 시작 신호의 startedAt이 기록과 같아야 한다
    expect(api.started.single.$3, run.startedAt);
    expect(controller.courseRunId, run.id);
    expect(controller.course?.name, '테스트 코스');
    expect(controller.selectedCourse, isNull);
  });

  test('free run does not call course APIs', () async {
    await controller.prepareStart();

    expect(controller.recorder.active, true);
    expect(api.prepared, isEmpty);
    expect(api.started, isEmpty);
    expect(controller.courseRunId, isNull);
  });

  test('offline start signal does not start the run', () async {
    api.startError = const ApiException(ApiException.network, 'offline');
    controller.selectCourse(const CourseSelection('course-1', '테스트 코스'));
    await controller.prepareStart();

    expect(controller.recorder.active, false);
    expect(controller.error, contains('인터넷'));
    expect(controller.selectedCourse?.courseId, 'course-1'); // 다시 시도할 수 있게 남긴다
  });

  test('unavailable course is not started and shows the server message', () async {
    api.prepareError = const ApiException('COURSE-002', '비공개되었거나 삭제된 코스입니다.', status: 409);
    controller.selectCourse(const CourseSelection('course-1', '테스트 코스'));
    await controller.prepareStart();

    expect(controller.recorder.active, false);
    expect(api.started, isEmpty);
    expect(controller.error, '비공개되었거나 삭제된 코스입니다.');
  });

  test('course cannot be changed while a run is active', () async {
    await controller.prepareStart();
    controller.selectCourse(const CourseSelection('course-1', '테스트 코스'));

    expect(controller.selectedCourse, isNull);
  });
}
