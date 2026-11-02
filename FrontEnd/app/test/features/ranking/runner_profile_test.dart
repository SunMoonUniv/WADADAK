import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/features/course/detail/course_rankings_screen.dart';
import 'package:wadadak/features/ranking/runner_profile_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseRankingApi rankings;
  late FakeMemberApi members;
  late FakeCourseApi courses;

  const route = [GeoPoint(37.52, 126.93), GeoPoint(37.53, 126.95)];
  const course = (courseId: 'c1', courseName: '한강 야경 5K', route: route, period: RankingPeriod.all);
  const runnerId = 'member-러너_하늘';

  RunnerCourse runnerCourse(String id, String name, int meters, double? rating, int completions) =>
      RunnerCourse.fromJson({
        'courseId': id,
        'name': name,
        'distanceMeters': meters,
        'averageRating': rating,
        'completionCount': completions,
        'route': [for (final point in route) {'lat': point.lat, 'lng': point.lng}],
      });

  /// G3(나 2위, 러너_하늘 1위) 위에 I3 · B1을 쌓는 라우터. [location]으로 바로 I3를 열 수도 있다.
  Future<void> open(WidgetTester tester, {String location = '/', Object? extra}) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      initialExtra: extra,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const CourseRankingsScreen(
            courseId: 'c1',
            courseName: '한강 야경 5K',
            route: route,
            period: RankingPeriod.all,
          ),
        ),
        GoRoute(
          path: '/runner/:memberId',
          builder: (_, state) => RunnerProfileScreen(
            memberId: state.pathParameters['memberId']!,
            course: state.extra as RunnerProfileCourse?,
          ),
        ),
        GoRoute(path: '/course/:courseId', builder: (_, state) => Text('B1 ${state.pathParameters['courseId']}')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rankingApiClientProvider.overrideWithValue(rankings),
        memberApiClientProvider.overrideWithValue(members),
        courseApiClientProvider.overrideWithValue(courses),
      ],
      child: MaterialApp.router(theme: WdTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  List<(String, String)> stats(WidgetTester tester) => tester.widget<WdStatSummary>(find.byType(WdStatSummary)).items;
  Finder rich(String text) => find.text(text, findRichText: true);

  setUp(() {
    final runners = [
      courseRankingEntry(1, '러너_하늘', 1452, pace: 279),
      courseRankingEntry(2, '러닝왕김', 1634, pace: 314, mine: true),
    ];
    rankings = FakeCourseRankingApi({RankingPeriod.all: courseRankingSummary(participants: 2, top: runners)})
      ..rows[RankingPeriod.all] = runners
      ..distanceTotals[runnerId] = {'totalDistanceMeters': 642300, 'runCount': 118}
      ..runnerRecords[runnerId] = {
        'runRecordId': 'r1',
        'rank': 1,
        'courseElapsedSeconds': 1452,
        'paceSecondsPerKm': 279,
        'completedAt': '2026-10-30T00:00:00Z',
        'myCourseElapsedSeconds': 1634,
      };
    members = FakeMemberApi()
      ..runnerProfiles[runnerId] = {
        'memberId': runnerId,
        'nickname': '러너_하늘',
        'profileImageUrl': null,
        'region': {'code': '1129000000', 'name': '성북구', 'fullName': '서울특별시 성북구'},
        'runningExperience': 'YEAR_1',
      };
    courses = FakeCourseApi()
      ..runnerCourseRows[runnerId] = [
        runnerCourse('k1', '한강 다리 왕복 8K', 8100, 4.4, 61),
        runnerCourse('k2', '정릉 오르막 4K', 4000, null, 23),
      ];
  });

  testWidgets('G3 runner row opens I3 with the course record and the registered courses (Figma I3)', (tester) async {
    await open(tester);

    await tester.tap(find.text('나 (러닝왕김)'));
    await tester.pumpAndSettle();
    expect(find.byType(RunnerProfileScreen), findsNothing, reason: '내 줄은 누를 수 없다');

    await tester.tap(find.text('러너_하늘'));
    await tester.pumpAndSettle();

    final appBar = tester.widget<WdAppBar>(find.byType(WdAppBar));
    expect((appBar.title, appBar.action), ('러너_하늘', null), reason: '신고 버튼은 없다');
    expect(find.text('성북구 · 러닝 1년+'), findsOneWidget, reason: '러닝 경력은 API 4단계 그대로');
    expect(stats(tester), [('총 거리', '642 km'), ('러닝', '118회'), ('등록 코스', '2개')]);
    expect(rankings.recordRequests, [('c1', runnerId, RankingPeriod.all)], reason: 'G3의 코스 · 기간으로 받는다');
    expect(find.text('이 코스에서의 기록'), findsOneWidget);
    expect(find.text('한강 야경 5K · 1위'), findsOneWidget);
    expect(find.text('24:12 · 4′39″/km'), findsOneWidget);
    expect(rich('러너_하늘보다 3분 02초 느려요'), findsOneWidget);
    expect(rich('내 최고 기록은 27:14예요'), findsOneWidget);
    expect(find.widgetWithText(WdButton, '이 기록과 대결하기'), findsOneWidget);
    expect(find.text('등록한 코스'), findsOneWidget);
    expect(find.text('8.1km · ★ 4.4 · 주행 61회'), findsOneWidget);
    expect(find.text('4.0km · 주행 23회'), findsOneWidget, reason: '리뷰가 없으면 평점은 빠진다');

    await tester.scrollUntilVisible(find.text('정릉 오르막 4K'), 200);
    await tester.tap(find.text('정릉 오르막 4K'));
    await tester.pumpAndSettle();
    expect(find.text('B1 k2'), findsOneWidget);
  });

  testWidgets('shows the gap when I am faster or equal, and no gap without my record', (tester) async {
    for (final (mine, gap) in [
      (1400, '러너_하늘보다 52초 빨라요'),
      (1452, '러너_하늘의 기록과 같아요'),
      (null, null),
    ]) {
      rankings.runnerRecords[runnerId] = {...rankings.runnerRecords[runnerId]!, 'myCourseElapsedSeconds': mine};
      await open(tester, location: '/runner/$runnerId', extra: course);

      if (gap == null) {
        expect(find.textContaining('내 최고 기록은', findRichText: true), findsNothing);
        expect(find.widgetWithText(WdButton, '이 기록과 대결하기'), findsOneWidget, reason: '내 기록이 없어도 대결할 수 있다');
      } else {
        expect(rich(gap), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('hides the record and dashes the totals of a private runner without courses', (tester) async {
    rankings
      ..distanceTotals[runnerId] = {'totalDistanceMeters': null, 'runCount': null}
      ..runnerRecords.remove(runnerId);
    courses.runnerCourseRows.remove(runnerId);
    await open(tester, location: '/runner/$runnerId', extra: course);

    expect(stats(tester), [('총 거리', '—'), ('러닝', '—'), ('등록 코스', '0개')]);
    expect(find.text('이 코스에서의 기록'), findsNothing, reason: '기록을 받지 못하면 섹션을 통째로 숨긴다');
    expect(find.text('등록한 코스'), findsNothing);
  });

  testWidgets('opened outside a course (E1 · I2 · I5) it does not ask a course record', (tester) async {
    await open(tester, location: '/runner/$runnerId');

    expect(rankings.recordRequests, isEmpty);
    expect(find.text('이 코스에서의 기록'), findsNothing);
    expect(find.text('등록한 코스'), findsOneWidget);
  });

  testWidgets('loads the next registered courses near the end', (tester) async {
    courses.runnerCourseRows[runnerId] = [
      for (var i = 1; i <= 25; i++) runnerCourse('k$i', '코스 $i', 5000, null, i),
    ];
    await open(tester, location: '/runner/$runnerId');
    expect(courses.runnerCourseRequests, [null]);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(courses.runnerCourseRequests, [null, '20']);
    expect(find.text('코스 25'), findsOneWidget);
  });

  testWidgets('does not open a withdrawn runner', (tester) async {
    await open(tester, location: '/runner/member-gone');

    expect(find.text(RunnerProfileScreen.unavailableTitle), findsOneWidget);
    expect(find.byType(WdStatSummary), findsNothing);
  });

  test('formats the record gap', () {
    expect([formatRecordGap(42), formatRecordGap(182), formatRecordGap(3602)], ['42초', '3분 02초', '1시간 00분 02초']);
  });
}
