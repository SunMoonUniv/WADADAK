import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/run/application/course_run_entry.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/presentation/course_select_screen.dart';

import '../fakes.dart';
import 'recording/run_controller_test.dart' show FailingStore, TestApi, TestLocation;

/// C8 코스 선택(Figma 1453:4434)
void main() {
  late RunController runs;
  late ProviderContainer container;
  late GoRouter router;

  Map<String, dynamic> record(String id, {String? courseId, String? courseName}) => {
    'id': id,
    'course': courseId == null ? null : {'courseId': courseId, 'courseName': courseName, 'completed': true},
  };

  Future<void> open(WidgetTester tester, {FakeCourseApi? courses}) async {
    sqfliteFfiInit();
    runs = RunController(FailingStore(), TestLocation(), TestApi(), () async => 'alice',
        wait: (_) async {}, lifecycleState: () => AppLifecycleState.resumed, automaticTicks: false);
    // shutdown은 기기 DB를 닫느라 위젯 테스트의 가짜 시간 안에서 끝나지 않는다. 여기서는 DB를 열지 않아 닫지 않는다
    router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('C6')),
      GoRoute(path: '/c8', builder: (_, _) => const CourseSelectScreen()),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        runControllerProvider.overrideWithValue(runs),
        courseApiClientProvider.overrideWithValue(courses ?? FakeCourseApi()),
        rankingApiClientProvider.overrideWithValue(FakeCourseRankingApi()),
        reviewApiClientProvider.overrideWithValue(FakeCourseReviewApi()),
        myLocationProvider.overrideWithValue(FakeMyLocation()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    container = ProviderScope.containerOf(tester.element(find.text('C6')));
    router.push('/c8');
    await tester.pumpAndSettle();
  }

  test('recent courses come from my record list, latest first, once per course', () {
    expect(
      recentCourses([
        record('r3', courseId: 'c2', courseName: '성북천 벚꽃길 3K'),
        record('r2'),
        record('r1', courseId: 'c1', courseName: '한강 야경 5K'),
        record('r0', courseId: 'c2', courseName: '성북천 벚꽃길 3K'),
      ]).map((c) => c.name),
      ['성북천 벚꽃길 3K', '한강 야경 5K'],
    );
  });

  testWidgets('picking a recent course sets it for the course run and goes back', (tester) async {
    await open(tester);
    runs.remoteRecords = [record('r1', courseId: 'c1', courseName: '한강 야경 5K')];
    runs.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('한강 야경 5K'), findsOneWidget);
    expect(find.text('아직 달린 기록 없음'), findsOneWidget);
    await tester.tap(find.text('한강 야경 5K'));
    await tester.pump();
    await tester.tap(find.text('이 코스로 설정'));
    await tester.pumpAndSettle();

    expect(find.text('C6'), findsOneWidget);
    expect(container.read(selectedCourseProvider)?.courseId, 'c1');
  });

  testWidgets('search shows matching courses and more can be revealed', (tester) async {
    await open(
      tester,
      courses: FakeCourseApi()
        ..searchable = [for (var i = 1; i <= 4; i++) testCourse('한강 코스 $i', averageRating: 4.5, activeRunners: i)],
    );
    await tester.enterText(find.byType(TextField), '한강');
    await tester.pumpAndSettle();

    expect(find.text('검색 결과'), findsOneWidget);
    expect(find.text('한강 코스 3'), findsOneWidget);
    expect(find.text('한강 코스 4'), findsNothing);
    await tester.dragUntilVisible(find.text('코스 1개 더 보기'), find.byType(ListView), const Offset(0, -200));
    await tester.tap(find.text('코스 1개 더 보기'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('한강 코스 4'), find.byType(ListView), const Offset(0, -200));
    expect(find.text('한강 코스 4'), findsOneWidget);
  });

  testWidgets('running without a course clears the chosen course', (tester) async {
    await open(tester);
    runs.selectCourse(const CourseSelection('c1', '한강 야경 5K'));
    await tester.tap(find.text('코스 없이 달리기'));
    await tester.pumpAndSettle();

    expect(find.text('C6'), findsOneWidget);
    expect(runs.selectedCourse, isNull);
  });
}
