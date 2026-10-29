import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/presentation/free_run_screen.dart';

import 'recording/run_controller_test.dart'
    show TestLocation, FailingStore, until;
import 'recording/course_run_start_test.dart' show CourseApi;

import 'package:geolocator/geolocator.dart';

class DriftingLocation extends TestLocation {
  double latitude = 36;
  @override
  Future<Position> currentPosition({LocationSettings? settings}) async =>
      point(latitude);
}

class PersistedStartApi extends CourseApi {
  DateTime? committed;
  bool loseFirstResponse = false;
  int calls = 0;
  Future<void> Function()? onAck;
  @override
  Future<void> startCourse(String owner, String id, DateTime startedAt) async {
    calls++;
    if (committed != null && committed != startedAt) {
      throw const ApiException('RUN-003', 'start time conflict', status: 409);
    }
    committed = startedAt;
    if (loseFirstResponse && calls == 1) {
      throw const ApiException(
        ApiException.network,
        'response lost after commit',
      );
    }
    await onAck?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestLocation location;
  late PersistedStartApi api;
  late RunController controller;
  setUp(() {
    sqfliteFfiInit();
    location = DriftingLocation();
    api = PersistedStartApi();
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
  Future<void> courseReady() async {
    controller.selectCourse(const CourseSelection('course-1', 'audit course'));
    await controller.prepareStart();
    expect(controller.courseStart, isNotNull);
  }

  test('AUDIT: lost course-start acknowledgement can retry the committed start', () async {
    await courseReady();
    api.loseFirstResponse = true;
    await controller.prepareStart();
    expect(controller.recorder.active, false);
    final committed = api.committed;
    location.clock = 6000;
    await controller.prepareStart();
    debugPrint(
      'AUDIT retry calls=${api.calls} committed=$committed error=${controller.error} active=${controller.recorder.active}',
    );
    expect(
      controller.recorder.active,
      true,
      reason: 'Retry must recover the server-committed start rather than remain stuck with 409.',
    );
  });
  test('AUDIT: delayed course-start acknowledgement preserves elapsed time', () async {
    await courseReady();
    api.onAck = () async {
      location.clock += 12000;
    };
    await controller.prepareStart();
    expect(controller.recorder.active, true);
    await controller.refreshMeasurement();
    debugPrint(
      'AUDIT delayed ack now=${location.utc} started=${controller.run!.startedAt} elapsedMs=${controller.metrics.elapsedMs}',
    );
    expect(
      controller.metrics.elapsedMs,
      12000,
      reason: 'Total elapsed time must include the interval since the committed course start.',
    );
  });
  test('AUDIT: fresh GPS outside the course start radius must stop countdown', () async {
    await courseReady();
    (location as DriftingLocation).latitude = 36.001;
    await controller.prepareStart();
    debugPrint(
      'AUDIT outside start active=${controller.recorder.active} serverStarts=${api.calls}',
    );
    expect(
      controller.recorder.active,
      false,
      reason: 'A fresh location about 111 metres outside the 20-metre start radius must not begin a course attempt.',
    );
  });
  testWidgets('AUDIT: dragging outside a start button cancels a pending hold', (
    tester,
  ) async {
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 64,
              child: RunHoldToStart(
                onStart: () {
                  starts++;
                },
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RunHoldToStart)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 1000));
    await gesture.up();
    debugPrint('AUDIT pointer moved outside starts=$starts');
    expect(
      starts,
      0,
      reason: 'A hold that leaves the button must not start recording.',
    );
  });
}
