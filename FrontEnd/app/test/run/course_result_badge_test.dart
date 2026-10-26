import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/application/run_result_mapper.dart';
import 'package:wadadak/features/run/presentation/free_run_result_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'run_result_mapper_ui_test.dart' show record;

/// D1(코스 완주 인정)·D1-1(미인정)·판정 대기 배지. 서버 판정(`Result.course`)만 보인다
void main() {
  Future<void> show(WidgetTester tester, {Map<String, dynamic>? course, String? pending}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
      child: MaterialApp(
        theme: WdTheme.light(),
        home: FreeRunResultView(
          run: remoteRunSnapshot({...record, 'course': ?course}),
          onConfirm: () {},
          pendingCourse: pending,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Map<String, dynamic> judged({required bool completed}) => {
    'courseId': 'c1',
    'courseName': '한강 야경 5K',
    'courseDistanceMeters': 5210,
    'completed': completed,
    'reason': completed ? 'COMPLETED' : 'FINISH_NOT_REACHED',
    'recognizedDistanceMeters': completed ? 5210.0 : 3800.0,
    'progressPercent': completed ? 100.0 : 72.9,
    'reviewEligible': true,
    'courseElapsedSeconds': 1634,
  };

  testWidgets('completed course run shows the D1 badge with the course name', (tester) async {
    await show(tester, course: judged(completed: true));

    expect(find.text('한강 야경 5K'), findsOneWidget);
    expect(find.textContaining('· 코스 완주'), findsOneWidget);
    expect(find.text('코스 완주 인정'), findsOneWidget);
    expect(find.text('한강 야경 5K · 5.2 km 완주'), findsOneWidget);
  });

  testWidgets('unfinished course run shows the D1-1 badge with the reason and recognized distance', (tester) async {
    await show(tester, course: judged(completed: false));

    expect(find.text('코스 완주 미인정'), findsOneWidget);
    expect(find.textContaining('코스 끝까지 도착하지 않았어요.'), findsOneWidget);
    expect(find.textContaining('코스 3.8 km(72%)까지 인정됐고'), findsOneWidget);
  });

  testWidgets('before the server judges it shows judging pending', (tester) async {
    await show(tester, pending: '한강 야경 5K');

    expect(find.text('한강 야경 5K'), findsOneWidget);
    expect(find.textContaining('· 판정 대기'), findsOneWidget);
    expect(find.text('코스 완주 판정 대기'), findsOneWidget);
  });

  testWidgets('free run has no course badge', (tester) async {
    await show(tester);

    expect(find.text('자유 러닝'), findsOneWidget);
    expect(find.textContaining('코스 완주'), findsNothing);
  });
}
