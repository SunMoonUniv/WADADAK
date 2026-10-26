import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/presentation/course_prep_view.dart';

import '../fakes.dart';

/// C6 달리기 준비 — 코스 러닝(Figma 1453:4196)
void main() {
  Future<void> show(
    WidgetTester tester, {
    required FakeCourseApi courses,
    CourseRankingSummary? ranking,
    ReviewSummary? reviews,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        courseApiClientProvider.overrideWithValue(courses),
        rankingApiClientProvider.overrideWithValue(FakeCourseRankingApi({RankingPeriod.all: ?ranking})),
        reviewApiClientProvider.overrideWithValue(FakeCourseReviewApi(reviews)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CourseRunPrep(course: CourseSelection('c1', '한강 야경 5K')))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  CourseDetail detail() => CourseDetail(
    courseId: 'c1',
    name: '한강 야경 5K',
    courseType: CourseType.custom,
    difficulty: Difficulty.medium,
    tags: const [CourseTag.flat],
    distanceMeters: 5210,
    route: const [GeoPoint(37.51, 126.99), GeoPoint(37.52, 127.0)],
    distanceMarkers: const [],
    expiresAt: DateTime.utc(2026, 12, 1),
    activeRunners: 3,
  );

  testWidgets('shows the course card and my best record on this course', (tester) async {
    await show(
      tester,
      courses: FakeCourseApi()..details = {'c1': detail()},
      ranking: courseRankingSummary(
        participants: 312,
        me: {'status': 'RANKED', 'rank': 24, 'courseElapsedSeconds': 1634, 'paceSecondsPerKm': 314},
      ),
      reviews: reviewSummary(count: 10, average: 4.6),
    );

    expect(find.text('익숙한 코스, 새로운 기록.'), findsOneWidget);
    expect(find.text('한강 야경 5K를 따라 끝까지 달려보세요.'), findsOneWidget);
    expect(find.text('5.2km · 난이도 중 · 평지'), findsOneWidget);
    expect(find.text('★ 4.6 · 지금 3명 달리는 중'), findsOneWidget);
    expect(find.text('27:14'), findsOneWidget);
    expect(find.text('평균 페이스 5′14″'), findsOneWidget);
    expect(find.text('코스 순위 24위 / 312명'), findsOneWidget);
  });

  testWidgets('without a finished record or course details it still shows the course name', (tester) async {
    await show(tester, courses: FakeCourseApi()); // 상세 실패(COURSE-001), 순위·리뷰 없음

    expect(find.text('한강 야경 5K'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('아직 완주 기록이 없어요'), findsOneWidget);
    expect(find.text('완주하면 코스 랭킹에 올라요'), findsOneWidget);
    expect(find.text('달리는 러너 없음'), findsOneWidget);
  });

  test('object particle follows the last syllable', () {
    expect(objectParticle('한강 야경 5K'), '를');
    expect(objectParticle('성북천 벚꽃길'), '을');
    expect(objectParticle('정릉 오르막'), '을');
    expect(objectParticle('남산 둘레'), '를');
  });
}
