import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/course_list_card.dart';
import 'package:wadadak/features/course/detail/course_detail_screen.dart';
import 'package:wadadak/features/course/course_public_period_sheet.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseApi courses;
  late FakeReviewSummaryApi reviews;

  const route = [GeoPoint(37.5666, 126.9784), GeoPoint(37.5700, 126.9800), GeoPoint(37.5750, 126.9850)];

  CourseDetail detail({String? nickname = '러닝왕김', DateTime? expiresAt}) => CourseDetail(
        courseId: 'c1',
        name: '한강 야경 5K',
        courseType: CourseType.custom,
        difficulty: Difficulty.medium,
        tags: const [CourseTag.flat, CourseTag.riverside, CourseTag.nightLight],
        distanceMeters: 5200,
        route: route,
        distanceMarkers: [for (var km = 1; km <= 5; km++) DistanceMarker(km, route[1])],
        expiresAt: expiresAt ?? DateTime.utc(2026, 11, 13, 14, 59, 59),
        creatorNickname: nickname,
      );

  /// 오늘은 2026-10-15(Asia/Seoul)다.
  final today = DateTime.utc(2026, 10, 15, 3);

  Future<void> openDetail(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mapEngineProvider.overrideWithValue(MapEngine.dev),
        courseApiClientProvider.overrideWithValue(courses),
        reviewApiClientProvider.overrideWithValue(reviews),
      ],
      child: MaterialApp(theme: WdTheme.light(), home: CourseDetailScreen(courseId: 'c1', now: () => today)),
    ));
    await tester.pumpAndSettle();
  }

  Finder text(String value) => find.text(value);
  String? tile(WidgetTester tester, String label) =>
      tester.widgetList<WdSummaryTile>(find.byType(WdSummaryTile)).firstWhere((tile) => tile.label == label).value;
  String snackBar(WidgetTester tester) =>
      ((tester.widget<SnackBar>(find.byType(SnackBar)).content as Text).data)!;

  setUp(() {
    courses = FakeCourseApi()..details = {'c1': detail()};
    reviews = FakeReviewSummaryApi(reviewSummary(count: 128, average: 4.6, items: (4.7, 4.4, 4.8, 4.1)));
  });

  testWidgets('shows the course with its creator, route, km markers, stats and runner ratings', (tester) async {
    await openDetail(tester);

    // 등록자 닉네임은 제목 아래(정책 공통 4 · B1-01)
    final appBar = tester.widget<WdAppBar>(find.byType(WdAppBar));
    expect(appBar.title, '한강 야경 5K');
    expect(appBar.subtitle, '등록자 러닝왕김');
    expect(text('등록자 러닝왕김'), findsOneWidget);
    // 유형 · 특징(FIL-04 순서)
    expect([for (final tag in tester.widgetList<WdTag>(find.byType(WdTag))) tag.label],
        ['그려서 만든 코스', '평지', '강변', '야간 조명']);
    expect(tile(tester, '거리'), '5.2km');
    expect(tile(tester, '난이도'), '중');
    expect(tile(tester, '평점'), '★ 4.6');
    expect(tile(tester, '평균 페이스'), '—', reason: '코스 통계(F11) 전');
    expect(text('리뷰 128'), findsOneWidget);

    final map = tester.widget<MapView>(find.byType(MapView));
    expect(map.lines.single.points, route);
    expect(map.markers.where((marker) => marker.id.startsWith('km-')), hasLength(5), reason: '1km마다 표지(B1-02)');
    final start = map.markers.singleWhere((marker) => marker.id == 'start');
    expect(start.position, route.first);
    expect(start.child, isA<WdCourseStartDot>(), reason: 'Figma B1 출발점은 이름표 없는 점');
    expect(text('1 km마다 지점 표시 · 총 5.2km'), findsOneWidget);
    expect(map.padding.top, greaterThan(0), reason: '경로를 위쪽 안내 문구 아래에 맞춘다');

    expect(text('러너 평가'), findsOneWidget);
    for (final (label, value) in [('안전성', '4.7'), ('도로 상태', '4.4'), ('야간 조명', '4.8'), ('편의시설', '4.1')]) {
      expect(find.descendant(of: find.ancestor(of: text(label), matching: find.byType(Row)), matching: text(value)),
          findsOneWidget);
    }
    expect(text('공개 기간이 29일 남았어요(11월 13일까지) · 누군가 완주하면 30일 연장돼요'), findsOneWidget);
    expect(text('이 코스로 달리기'), findsOneWidget);
    expect(text('고스트 대결 ▶'), findsOneWidget, reason: 'Figma B1');
    expect(find.byWidgetPredicate((widget) => widget is WdIcon && widget.icon == WdIcons.share), findsNothing,
        reason: '공유 링크를 정할 때까지 공유는 두지 않는다');
  });

  testWidgets('tells nobody has run it yet when there is no review (Figma B1-1)', (tester) async {
    reviews.result = reviewSummary();
    await openDetail(tester);

    expect(tile(tester, '평점'), '—');
    expect(text('리뷰 0'), findsOneWidget);
    expect(text(CourseDetailScreen.noRunnerTitle), findsOneWidget);
    expect(text(CourseDetailScreen.noRunnerMessage), findsOneWidget);
    expect(text('러너 평가'), findsNothing);
  });

  testWidgets('shows a withdrawn creator as such (common 4)', (tester) async {
    courses.details = {'c1': detail(nickname: '탈퇴한 사용자')};
    await openDetail(tester);

    expect(tester.widget<WdAppBar>(find.byType(WdAppBar)).subtitle, '등록자 탈퇴한 사용자');
  });

  testWidgets('leaves the creator out when the server could not read it', (tester) async {
    courses.details = {'c1': detail(nickname: null)};
    await openDetail(tester);

    expect(tester.widget<WdAppBar>(find.byType(WdAppBar)).subtitle, isNull);
    expect(find.textContaining('등록자'), findsNothing);
    expect(text('한강 야경 5K'), findsOneWidget);
  });

  testWidgets('stays on the info tab and tells the review, ranking and run screens are not ready', (tester) async {
    await openDetail(tester);

    await tester.tap(text('리뷰 128'));
    await tester.pumpAndSettle();
    expect(snackBar(tester), '리뷰 탭은 아직 준비 중이에요.');
    expect(text('러너 평가'), findsOneWidget);

    await tester.tap(text('랭킹'));
    await tester.pumpAndSettle();
    expect(snackBar(tester), '랭킹 탭은 아직 준비 중이에요.');

    await tester.tap(text('이 코스로 달리기'));
    await tester.pumpAndSettle();
    expect(snackBar(tester), CourseDetailScreen.runNotReadyMessage);
    await tester.tap(text('고스트 대결 ▶'));
    await tester.pumpAndSettle();
    expect(snackBar(tester), CourseDetailScreen.runNotReadyMessage);
  });

  testWidgets('does not open the public period sheet (B11) from the period notice', (tester) async {
    await openDetail(tester);

    await tester.tap(find.textContaining('공개 기간이'));
    await tester.pumpAndSettle();
    expect(text(CoursePublicPeriodSheet.title), findsNothing, reason: 'B11은 코스를 만들 때만 띄운다(4.1 B11)');
  });

  testWidgets('does not open a hidden or deleted course (B1-04)', (tester) async {
    courses.detailError = const ApiException(CourseApiClient.courseNotAvailableCode, '비공개되었거나 삭제된 코스입니다.', status: 409);
    await openDetail(tester);

    expect(text(CourseDetailScreen.unavailableTitle), findsOneWidget);
    expect(text(CourseDetailScreen.unavailableMessage), findsOneWidget);
    expect(text('이 코스로 달리기'), findsNothing);
  });

  testWidgets('offers to retry when the course cannot be loaded', (tester) async {
    courses.detailError = const ApiException('NETWORK', '');
    await openDetail(tester);
    expect(text(CourseDetailScreen.loadFailedTitle), findsOneWidget);

    courses.detailError = null;
    await tester.tap(text('다시 시도'));
    await tester.pumpAndSettle();
    expect(text('한강 야경 5K'), findsOneWidget);
    expect(courses.detailRequests, ['c1', 'c1']);
  });

  testWidgets('keeps the course and offers to retry when the ratings cannot be loaded', (tester) async {
    reviews.error = const ApiException('NETWORK', '');
    await openDetail(tester);

    expect(text('한강 야경 5K'), findsOneWidget);
    expect(tile(tester, '평점'), '—');
    expect(text('평가를 불러오지 못했어요.'), findsOneWidget);

    reviews.error = null;
    await tester.tap(text('다시 시도'));
    await tester.pumpAndSettle();
    expect(text('안전성'), findsOneWidget);
    expect(tile(tester, '평점'), '★ 4.6');
  });

  test('says the last public day as today', () {
    final lastDay = DateTime.utc(2026, 10, 15, 14, 59, 59);
    expect(publicPeriodText(lastDay, today), '오늘까지 공개돼요 · 누군가 완주하면 30일 연장돼요');
    expect(publicPeriodText(DateTime.utc(2026, 10, 16, 14, 59, 59), today),
        '공개 기간이 1일 남았어요(10월 16일까지) · 누군가 완주하면 30일 연장돼요');
  });

  group('from home', () {
    late FakeMyLocation location;

    final card = testCourse('한강 야경 5K', courseId: 'c1', route: route);

    Future<void> openHome(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(402, 874)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          memberApiClientProvider.overrideWithValue(FakeMemberApi()),
          tokenStorageProvider.overrideWithValue(MemoryTokenStorage(testTokens)),
          socialLoginProvider.overrideWithValue(FakeSocialLogin()),
          runPermissionsProvider.overrideWithValue(FakeRunPermissions()),
          mapEngineProvider.overrideWithValue(MapEngine.dev),
          courseApiClientProvider.overrideWithValue(courses),
          reviewApiClientProvider.overrideWithValue(reviews),
          myLocationProvider.overrideWithValue(location),
        ],
        child: const WadadakApp(),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() {
      courses
        ..onMap = [card]
        ..listed = [card];
      location = FakeMyLocation(location: const GeoPoint(37.5593, 126.9784));
    });

    testWidgets('a course card opens the detail, and back keeps the home as it was (FIL-08)', (tester) async {
      await openHome(tester);
      await tester.tap(find.widgetWithText(WdFilterChip, '가까운순'));
      await tester.pumpAndSettle();
      final listRequests = courses.listRequests.length;
      final mapRequests = courses.mapRequests.length;

      await tester.tap(find.byType(CourseListCard));
      await tester.pumpAndSettle();
      expect(find.byType(CourseDetailScreen), findsOneWidget);
      expect(courses.detailRequests, ['c1']);

      await tester.tap(find.bySemanticsLabel('뒤로 가기'));
      await tester.pumpAndSettle();
      expect(find.byType(CourseDetailScreen), findsNothing);
      expect(tester.widget<WdFilterChip>(find.widgetWithText(WdFilterChip, '가까운순')).selected, isTrue,
          reason: '정렬 그대로');
      expect(courses.listRequests.length, listRequests, reason: '목록을 다시 받지 않아 스크롤도 그대로다');
      expect(courses.mapRequests.length, mapRequests, reason: '지도 자리 그대로');
    });
  });
}
