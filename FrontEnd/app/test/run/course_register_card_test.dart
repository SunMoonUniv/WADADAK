import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/features/run/application/run_result_mapper.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/course_register_card.dart';

import '../fakes.dart';
import 'run_result_mapper_ui_test.dart' show record;

/// 결과 화면 `달린 경로로 코스 만들기`(정책 공통 3, B6-04·B6-06)
void main() {
  RunSnapshot run({double distance = 1500, bool? passed = true, String id = 'r1'}) => RunSnapshot(
    state: RunState.finished,
    sessionId: id,
    startedAt: DateTime.utc(2026, 10, 27),
    elapsed: const Duration(minutes: 10),
    active: const Duration(minutes: 10),
    distanceMeters: distance,
    inputs: const [],
    gpsGapPassed: passed,
  );

  const quota = RegistrationQuota(
    custom: TypeQuota(limit: 1, remaining: 1),
    gps: TypeQuota(limit: 3, remaining: 2),
    usedRunRecordIds: ['used'],
  );

  test('blocks for under 1 km, not yet uploaded, GPS gaps and already registered, in that order', () {
    expect(registerBlocker(run(distance: 900, passed: null), quota), '1km 이상 달린 기록만 등록할 수 있어요');
    expect(registerBlocker(run(passed: null), quota), '기록을 서버에 올린 뒤 등록할 수 있어요');
    expect(registerBlocker(run(passed: false), quota), 'GPS가 끊긴 구간이 있어 등록할 수 없어요');
    expect(registerBlocker(run(id: 'used'), quota), '이미 코스로 등록한 기록이에요');
    expect(registerBlocker(run(), quota), isNull);
    expect(registerBlocker(run(), null), isNull); // 한도 조회가 안 되면 막지 않는다(D4에서 서버가 다시 본다)
  });

  test('server result carries the GPS gap check', () {
    expect(remoteRunSnapshot({...record, 'gpsGap': {'passed': false, 'version': 'GPS_GAP_V1'}}).gpsGapPassed, false);
    expect(remoteRunSnapshot(record).gpsGapPassed, isNull);
  });

  Future<void> show(WidgetTester tester, RunSnapshot value, RegistrationQuota q) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [courseApiClientProvider.overrideWithValue(FakeCourseApi()..quota = q)],
      child: MaterialApp(home: Scaffold(body: CourseRegisterCard(run: value))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('registrable record opens course registration', (tester) async {
    await show(tester, run(), quota);
    expect(find.text('코스로 등록할 수 있어요'), findsOneWidget);
    expect(find.text('달린 경로가 그대로 코스가 돼요'), findsOneWidget);
    await tester.tap(find.text('코스로 등록'));
    await tester.pumpAndSettle();
    expect(find.text('코스 정보 입력 화면은 준비 중이에요.'), findsOneWidget);
  });

  testWidgets('used up daily quota shows the limit instead of moving on (B6-06)', (tester) async {
    await show(
      tester,
      run(),
      const RegistrationQuota(custom: TypeQuota(limit: 1, remaining: 1), gps: TypeQuota(limit: 3, remaining: 0)),
    );
    await tester.tap(find.text('코스로 등록'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3개까지 등록할 수 있어요'), findsOneWidget);
  });

  testWidgets('blocked record shows the reason and does nothing on tap', (tester) async {
    await show(tester, run(id: 'used'), quota);

    expect(find.text('코스로 등록할 수 없어요'), findsOneWidget);
    expect(find.text('이미 코스로 등록한 기록이에요'), findsOneWidget);
    await tester.tap(find.text('코스로 등록'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
