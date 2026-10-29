import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/course/course_list_card.dart';
import 'package:wadadak/features/course/detail/course_detail_screen.dart';
import 'package:wadadak/features/course/detail/course_ranking_tab.dart';
import 'package:wadadak/features/course/detail/course_rankings_screen.dart';
import 'package:wadadak/features/course/detail/course_reviews_tab.dart';
import 'package:wadadak/features/course/detail/course_run_bar.dart';
import 'package:wadadak/features/course/course_public_period_sheet.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/features/review/review_list_screen.dart';
import 'package:wadadak/features/review/review_state.dart';
import 'package:wadadak/features/review/review_widgets.dart';
import 'package:wadadak/features/run/application/course_run_entry.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseApi courses;
  late FakeCourseReviewApi reviews;
  late FakeCourseRankingApi rankings;

  const route = [GeoPoint(37.5666, 126.9784), GeoPoint(37.5700, 126.9800), GeoPoint(37.5750, 126.9850)];

  CourseDetail detail({String? nickname = '러닝왕김', DateTime? expiresAt, int? pace, int activeRunners = 0}) => CourseDetail(
        courseId: 'c1',
        name: '한강 야경 5K',
        courseType: CourseType.custom,
        difficulty: Difficulty.medium,
        tags: const [CourseTag.flat, CourseTag.riverside, CourseTag.nightLight],
        distanceMeters: 5200,
        route: route,
        distanceMarkers: [for (var km = 1; km <= 5; km++) DistanceMarker(km, route[1])],
        expiresAt: expiresAt ?? DateTime.utc(2026, 11, 13, 14, 59, 59),
        averagePaceSecondsPerKm: pace,
        creatorNickname: nickname,
        activeRunners: activeRunners,
      );

  /// Figma B9: 312명 중 나 24위(27:14 · 5′14″/km · 09.08 · 상위 8%), 1위 24:12, 평균 28:40. 공개 고스트는 1위.
  CourseRankingSummary allRanking({
    Map<String, Object?> me = const {
      'status': 'RANKED',
      'rank': 24,
      'nickname': '러닝왕김',
      'courseElapsedSeconds': 1634,
      'paceSecondsPerKm': 314,
      'completedAt': '2026-09-08T01:00:00Z',
      'topPercent': 8,
    },
  }) =>
      courseRankingSummary(
        participants: 312,
        average: 1720,
        me: me,
        top: [
          courseRankingEntry(1, '러너_하늘', 1452, pace: 279),
          courseRankingEntry(2, '러너_민', 1488, pace: 286),
          courseRankingEntry(3, '성북러너', 1502, pace: 289),
          courseRankingEntry(4, '달리는곰', 1520, pace: 292),
          courseRankingEntry(5, '한강러너', 1544, pace: 297),
        ],
        ghost: 1,
      );

  /// 이번 주: 3명 중 나 2위. 공개 고스트는 1위.
  final weekRanking = courseRankingSummary(
    participants: 3,
    average: 1510,
    me: const {
      'status': 'RANKED',
      'rank': 2,
      'courseElapsedSeconds': 1500,
      'paceSecondsPerKm': 288,
      'completedAt': '2026-10-14T01:00:00Z',
      'topPercent': 67,
    },
    top: [
      courseRankingEntry(1, '새벽러닝', 1490, pace: 287),
      courseRankingEntry(2, '러닝왕김', 1500, pace: 288, mine: true),
      courseRankingEntry(3, '야경러너', 1540, pace: 296),
    ],
    ghost: 1,
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
        rankingApiClientProvider.overrideWithValue(rankings),
      ],
      child: MaterialApp(theme: WdTheme.light(), home: CourseDetailScreen(courseId: 'c1', now: () => today)),
    ));
    await tester.pumpAndSettle();
  }

  Finder text(String value) => find.text(value);
  String? tile(WidgetTester tester, String label) =>
      tester.widgetList<WdSummaryTile>(find.byType(WdSummaryTile)).firstWhere((tile) => tile.label == label).value;
  /// G2에서 돌아올 때처럼 요약 · 미리보기를 다시 받게 한다.
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(CourseDetailScreen)));
  /// 아래 버튼(라벨, 켜짐).
  List<(String, bool)> bottomButtons(WidgetTester tester) => [
        for (final button in tester.widgetList<WdButton>(
            find.descendant(of: find.byType(WdBottomBar), matching: find.byType(WdButton))))
          (button.label, button.onPressed != null),
      ];

  setUp(() {
    courses = FakeCourseApi()..details = {'c1': detail()};
    reviews = FakeCourseReviewApi(reviewSummary(count: 128, average: 4.6, items: (4.7, 4.4, 4.8, 4.1)));
    rankings = FakeCourseRankingApi({RankingPeriod.all: allRanking()});
  });

  testWidgets('shows the average pace of every completion (Figma B1 5′14″)', (tester) async {
    courses.details = {'c1': detail(pace: 314)};
    await openDetail(tester);

    expect(tile(tester, '평균 페이스'), '5′14″');
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
    expect(tile(tester, '평균 페이스'), '—', reason: '아직 아무도 완주하지 않았다');
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
    expect(bottomButtons(tester), [('이 코스로 달리기', true), ('고스트 대결 ▶', true)], reason: 'Figma B1');
    expect(rankings.summaryRequests, [RankingPeriod.all], reason: 'B1 고스트는 전체 기간(B1-07)');
    expect(find.byWidgetPredicate((widget) => widget is WdIcon && widget.icon == WdIcons.share), findsNothing,
        reason: '공유 링크를 정할 때까지 공유는 두지 않는다');
  });

  testWidgets('shows the runners on the course now at the bottom right of the map (Figma B1 Live runners)', (tester) async {
    courses.details = {'c1': detail(activeRunners: 3)};
    await openDetail(tester);

    final map = tester.getRect(find.byType(MapView));
    final badge = tester.getRect(text('지금 3명 달리는 중'));
    expect(map.contains(badge.center), isTrue);
    expect(badge.center.dx, greaterThan(map.center.dx), reason: '오른쪽');
    expect(badge.center.dy, greaterThan(map.center.dy), reason: '아래');
    expect(tester.widget<Text>(text('지금 3명 달리는 중')).style?.color, WdColors.green);
  });

  testWidgets('tells nobody is running the course now (B1-01)', (tester) async {
    await openDetail(tester);

    expect(text('달리는 러너 없음'), findsOneWidget);
    expect(tester.widget<Text>(text('달리는 러너 없음')).style?.color, WdColors.muted);
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

  testWidgets('picks this course and no longer shows the obsolete ghost placeholder', (tester) async {
    await openDetail(tester);

    await tester.tap(text('이 코스로 달리기'));
    await tester.pumpAndSettle();
    final picked = container(tester).read(selectedCourseProvider);
    expect((picked?.courseId, picked?.name), ('c1', '한강 야경 5K'));
    await tester.tap(text('고스트 대결 ▶'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
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

  testWidgets('keeps the runner ratings and offers to retry when refreshing them fails', (tester) async {
    await openDetail(tester);
    reviews.error = const ApiException('NETWORK', '');
    container(tester).invalidate(reviewSummaryProvider('c1'));
    await tester.pumpAndSettle();
    expect(text('안전성'), findsOneWidget, reason: '받아 둔 평가는 그대로');
    expect(tile(tester, '평점'), '★ 4.6');
    expect(text(CourseReviewsTab.staleSummaryMessage), findsOneWidget);

    reviews.error = null;
    await tester.tap(text('다시 시도'));
    await tester.pumpAndSettle();
    expect(text(CourseReviewsTab.staleSummaryMessage), findsNothing);
    expect(reviews.requests, 3);
  });

  test('says the last public day as today', () {
    final lastDay = DateTime.utc(2026, 10, 15, 14, 59, 59);
    expect(publicPeriodText(lastDay, today), '오늘까지 공개돼요 · 누군가 완주하면 30일 연장돼요');
    expect(publicPeriodText(DateTime.utc(2026, 10, 16, 14, 59, 59), today),
        '공개 기간이 1일 남았어요(10월 16일까지) · 누군가 완주하면 30일 연장돼요');
  });

  test('drops the extension hint once the current period is already extended', () {
    expect(publicPeriodText(DateTime.utc(2026, 11, 13, 14, 59, 59), today),
        '공개 기간이 29일 남았어요(11월 13일까지) · 누군가 완주하면 30일 연장돼요');
    expect(publicPeriodText(DateTime.utc(2026, 11, 14, 14, 59, 59), today), '공개 기간이 30일 남았어요(11월 14일까지)');
    expect(publicPeriodText(DateTime.utc(2026, 12, 13, 14, 59, 59), today), '공개 기간이 59일 남았어요(12월 13일까지)');
  });

  group('review tab (B8)', () {
    const latest = (sort: ReviewSort.latest, photoOnly: false, excludeMine: false);

    setUp(() {
      reviews
        ..result = reviewSummary(
          count: 128,
          average: 4.6,
          items: (4.7, 4.4, 4.8, 4.1),
          counts: (92, 26, 6, 3, 1),
        )
        ..cards = [reviewCard('러닝왕김', mine: true), reviewCard('러너_하늘'), reviewCard('새벽러닝', rating: 4)];
    });

    Future<void> openReviews(WidgetTester tester) async {
      await openDetail(tester);
      await tester.tap(text('리뷰 128'));
      await tester.pumpAndSettle();
    }

    List<String> chips(WidgetTester tester) => [
          for (final chip in tester.widgetList<WdFilterChip>(find.byType(WdFilterChip)))
            '${chip.label}${chip.selected ? '*' : ''}',
        ];
    bool photoOnly(WidgetTester tester) =>
        tester.widget<ReviewPhotoOnlyCheck>(find.byType(ReviewPhotoOnlyCheck)).checked;

    testWidgets('shows the rating summary, item averages and the first two reviews', (tester) async {
      await openReviews(tester);

      expect(text('4.6'), findsOneWidget);
      expect(text('★ ★ ★ ★ ☆'), findsOneWidget);
      expect(text('리뷰 128'), findsNWidgets(2), reason: '탭 이름 · 요약');
      final bars = tester.widgetList<WdProgressBar>(find.byType(WdProgressBar)).map((bar) => bar.value);
      expect(bars, [92 / 128, 26 / 128, 6 / 128, 3 / 128, 1 / 128], reason: '5점부터');

      expect(text('항목별 평균'), findsOneWidget);
      for (final (label, value) in [('안전성', '4.7'), ('도로 상태', '4.4'), ('야간 조명', '4.8'), ('편의시설', '4.1')]) {
        expect(tile(tester, label), value);
      }
      expect(text('러너 평가'), findsNothing, reason: '정보 탭 내용은 숨는다');

      expect(chips(tester), ['최신순*', '높은 평점', '낮은 평점']);
      expect(photoOnly(tester), isFalse, reason: '사진은 G2처럼 오른쪽 체크박스');
      expect(reviews.listRequests, [latest], reason: '내 리뷰도 함께 받는다');
      expect([for (final card in tester.widgetList<WdReviewCard>(find.byType(WdReviewCard))) card.author],
          ['나 (러닝왕김)', '러너_하늘'], reason: 'Figma B8처럼 두 개');
      expect(text('리뷰 128개 모두 보기'), findsOneWidget);
      expect(find.textContaining('공개 기간이'), findsOneWidget, reason: '어느 탭에서나 보인다');
    });

    testWidgets('sorts and filters photos, keeping the choice across tabs', (tester) async {
      await openReviews(tester);

      await tester.tap(text('높은 평점'));
      await tester.pumpAndSettle();
      await tester.tap(text('사진 리뷰만'));
      await tester.pumpAndSettle();
      expect(reviews.listRequests.skip(1), [
        (sort: ReviewSort.highest, photoOnly: false, excludeMine: false),
        (sort: ReviewSort.highest, photoOnly: true, excludeMine: false),
      ]);
      expect(chips(tester), ['최신순', '높은 평점*', '낮은 평점']);
      expect(photoOnly(tester), isTrue);
      expect(text('사진이 있는 리뷰가 아직 없어요.'), findsOneWidget);

      await tester.tap(text('정보'));
      await tester.pumpAndSettle();
      expect(text('러너 평가'), findsOneWidget);
      await tester.tap(text('리뷰 128'));
      await tester.pumpAndSettle();
      expect(chips(tester), ['최신순', '높은 평점*', '낮은 평점'], reason: 'B8-03 선택 유지');
      expect(photoOnly(tester), isTrue);
      expect(reviews.listRequests, hasLength(3), reason: '탭을 오가도 다시 받지 않는다');
    });

    testWidgets('keeps the shown reviews while another sort is loading, so the page does not jump', (tester) async {
      await openReviews(tester);
      reviews.listGate = Completer<void>();

      await tester.tap(text('높은 평점'));
      await tester.pump();
      expect(find.byType(WdReviewCard), findsNWidgets(2), reason: '받는 동안 이전 카드 그대로');
      expect(find.byType(CircularProgressIndicator), findsNothing);

      reviews.listGate!.complete();
      await tester.pumpAndSettle();
      expect(reviews.listRequests.last.sort, ReviewSort.highest);
      expect(find.byType(WdReviewCard), findsNWidgets(2));
    });

    testWidgets('shows B8-1 when nobody has reviewed and does not ask for the list', (tester) async {
      reviews.result = reviewSummary();
      await openDetail(tester);
      await tester.tap(text('리뷰 0'));
      await tester.pumpAndSettle();

      expect(text(CourseReviewsTab.emptyTitle), findsOneWidget);
      expect(text(CourseReviewsTab.emptyMessage), findsOneWidget);
      expect(find.byType(WdFilterChip), findsNothing);
      expect(find.byType(ReviewPhotoOnlyCheck), findsNothing);
      expect(find.textContaining('모두 보기'), findsNothing);
      expect(reviews.listRequests, isEmpty);
      expect(find.textContaining('공개 기간이'), findsOneWidget);
    });

    testWidgets('offers to retry the reviews and keeps the chosen sort', (tester) async {
      reviews.listError = const ApiException('NETWORK', '');
      await openReviews(tester);
      expect(text(CourseReviewsTab.failedMessage), findsOneWidget);
      expect(text('리뷰 128개 모두 보기'), findsOneWidget, reason: '요약은 받았다');

      await tester.tap(text('낮은 평점'));
      await tester.pumpAndSettle();
      expect(text(CourseReviewsTab.failedMessage), findsOneWidget);
      expect(chips(tester).first, '최신순');
      expect(chips(tester)[2], '낮은 평점*');

      reviews.listError = null;
      await tester.tap(text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.byType(WdReviewCard), findsNWidgets(2));
      expect(reviews.listRequests.last.sort, ReviewSort.lowest);
    });

    testWidgets('offers to retry when the summary cannot be loaded', (tester) async {
      reviews.error = const ApiException('NETWORK', '');
      await openDetail(tester);
      await tester.tap(text('리뷰'));
      await tester.pumpAndSettle();
      expect(text(CourseReviewsTab.failedMessage), findsOneWidget);
      expect(reviews.listRequests, isEmpty);

      reviews.error = null;
      await tester.tap(text('다시 시도'));
      await tester.pumpAndSettle();
      expect(text('리뷰 128'), findsNWidgets(2));
      expect(find.byType(WdReviewCard), findsNWidgets(2));
    });

    testWidgets('keeps the summary and offers to retry when refreshing it fails (B8-02)', (tester) async {
      await openReviews(tester);
      reviews.error = const ApiException('NETWORK', '');
      container(tester).invalidate(reviewSummaryProvider('c1'));
      await tester.pumpAndSettle();
      expect(text('4.6'), findsOneWidget, reason: '받아 둔 요약은 그대로');
      expect(find.byType(WdReviewCard), findsNWidgets(2));
      expect(text(CourseReviewsTab.staleSummaryMessage), findsOneWidget);

      reviews
        ..error = null
        ..result = reviewSummary(count: 129, average: 4.7, items: (4.7, 4.4, 4.8, 4.1));
      await tester.tap(text('다시 시도'));
      await tester.pumpAndSettle();
      expect(text(CourseReviewsTab.staleSummaryMessage), findsNothing);
      expect(text('4.7'), findsWidgets);
      expect(text('리뷰 129'), findsNWidgets(2));
    });

    testWidgets('keeps the reviews and offers to retry when refreshing them fails (B8-03)', (tester) async {
      await openReviews(tester);
      reviews.listError = const ApiException('NETWORK', '');
      container(tester).invalidate(courseReviewPreviewProvider);
      await tester.pumpAndSettle();
      expect(find.byType(WdReviewCard), findsNWidgets(2), reason: '받아 둔 리뷰는 그대로');
      expect(text(CourseReviewsTab.stalePreviewMessage), findsOneWidget);
      expect(text(CourseReviewsTab.failedMessage), findsNothing);

      reviews.listError = null;
      await tester.ensureVisible(text('다시 시도'));
      await tester.pumpAndSettle();
      await tester.tap(text('다시 시도'));
      await tester.pumpAndSettle();
      expect(text(CourseReviewsTab.stalePreviewMessage), findsNothing);
      expect(reviews.listRequests, hasLength(3));
    });
  });

  group('ranking tab (B9)', () {
    Future<void> openRanking(WidgetTester tester) async {
      await openDetail(tester);
      await tester.tap(text('랭킹'));
      await tester.pumpAndSettle();
    }

    List<String> chips(WidgetTester tester) => [
          for (final chip in tester.widgetList<WdFilterChip>(find.byType(WdFilterChip)))
            '${chip.label}${chip.selected ? '*' : ''}',
        ];
    WdRank myRank(WidgetTester tester) => tester.widget<WdMyRankCard>(find.byType(WdMyRankCard)).data;
    List<(String, String)> stats(WidgetTester tester) => tester.widget<WdStatSummary>(find.byType(WdStatSummary)).items;
    List<WdRank> ranks(WidgetTester tester) => tester.widget<WdRankList>(find.byType(WdRankList)).ranks;
    Future<void> pull(WidgetTester tester) async {
      await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
    }

    testWidgets('shows my rank, the course stats and the top five (Figma B9)', (tester) async {
      await openRanking(tester);

      expect(chips(tester), ['전체 기간*', '이번 달', '이번 주']);
      final me = myRank(tester);
      expect([me.rank, me.name, me.meta, me.value], ['24', '나 (러닝왕김)', '5′14″/km · 09.08 · 상위 8%', '27:14']);
      expect(tester.widget<WdMyRankCard>(find.byType(WdMyRankCard)).onTap, isNull, reason: '내 순위는 누를 수 없다(B9-02)');
      expect(stats(tester), [('참여 러너', '312명'), ('1위 기록', '24:12'), ('평균 기록', '28:40')]);
      expect([for (final rank in ranks(tester)) '${rank.rank} ${rank.name} ${rank.meta} ${rank.value}'], [
        '1 러너_하늘 4′39″/km 24:12',
        '2 러너_민 4′46″/km 24:48',
        '3 성북러너 4′49″/km 25:02',
        '4 달리는곰 4′52″/km 25:20',
        '5 한강러너 4′57″/km 25:44',
      ]);
      expect(tester.widget<WdRankList>(find.byType(WdRankList)).onTap, isNull, reason: 'I3가 생길 때까지');
      expect(text('전체 순위 312명 보기'), findsOneWidget);
      expect(find.textContaining('공개 기간이'), findsOneWidget, reason: '어느 탭에서나 보인다');
      expect(bottomButtons(tester), [('이 코스로 달리기', true), ('고스트 대결 ▶', true)]);
      expect(rankings.summaryRequests, [RankingPeriod.all], reason: '고스트 버튼과 같은 요약을 쓴다');
    });

    testWidgets('changes the period, keeping the shown ranking while loading and the choice across tabs',
        (tester) async {
      rankings.summaries[RankingPeriod.week] = weekRanking;
      await openRanking(tester);
      rankings.gate = Completer<void>();

      await tester.tap(text('이번 주'));
      await tester.pump();
      expect(chips(tester), ['전체 기간', '이번 달', '이번 주*']);
      expect(myRank(tester).rank, '24', reason: '받는 동안 보이던 랭킹 그대로');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(bottomButtons(tester).last, ('고스트 대결 ▶', false), reason: '고른 기간의 고스트를 받는 중');

      rankings.gate!.complete();
      rankings.gate = null;
      await tester.pumpAndSettle();
      expect(myRank(tester).meta, '4′48″/km · 10.14 · 상위 67%');
      expect(myRank(tester).name, '나', reason: '닉네임을 못 받으면 `나`만');
      expect([for (final rank in ranks(tester)) rank.name], ['새벽러닝', '나 (러닝왕김)', '야경러너'],
          reason: '내 줄은 B8 리뷰처럼 `나 (닉네임)`');
      expect(text('전체 순위 3명 보기'), findsOneWidget);
      expect(bottomButtons(tester).last, ('고스트 대결 ▶', true));
      expect(rankings.summaryRequests, [RankingPeriod.all, RankingPeriod.week]);

      await tester.tap(text('정보'));
      await tester.pumpAndSettle();
      expect(text('러너 평가'), findsOneWidget);
      await tester.tap(text('랭킹'));
      await tester.pumpAndSettle();
      expect(chips(tester).last, '이번 주*', reason: '탭을 오가도 기간은 그대로');
      expect(rankings.summaryRequests, hasLength(2), reason: '탭을 오가도 다시 받지 않는다');

      await tester.tap(text('전체 기간'));
      await tester.pumpAndSettle();
      expect(rankings.summaryRequests, [RankingPeriod.all, RankingPeriod.week, RankingPeriod.all],
          reason: '기간을 바꾸면 받아 둔 것이 있어도 다시 받는다(B9-01)');
      expect(myRank(tester).rank, '24');
    });

    testWidgets('shows B9-1 with the first-run button when nobody has finished', (tester) async {
      rankings.summaries = {};
      await openDetail(tester);
      expect(bottomButtons(tester), [('고스트 없음', false), (CourseRunBar.firstRunLabel, true)], reason: 'B1-1도 같다');

      await tester.tap(text('랭킹'));
      await tester.pumpAndSettle();
      expect(text(CourseRankingTab.emptyTitle), findsOneWidget);
      expect(text(CourseRankingTab.emptyMessage), findsOneWidget);
      expect(find.byType(WdFilterChip), findsNothing, reason: 'Figma B9-1');
      expect(find.byType(WdMyRankCard), findsNothing);
      expect(find.textContaining('전체 순위'), findsNothing);
      expect(find.textContaining('공개 기간이'), findsOneWidget);
      expect(bottomButtons(tester), [('고스트 없음', false), (CourseRunBar.firstRunLabel, true)]);

      await tester.tap(text(CourseRunBar.firstRunLabel));
      await tester.pumpAndSettle();
      expect(container(tester).read(selectedCourseProvider)?.courseId, 'c1', reason: '첫 번째로 달리기도 코스 러닝');
    });

    testWidgets('shows zero runners and dashes for a period without records (B9-03)', (tester) async {
      await openRanking(tester);
      await tester.tap(text('이번 달'));
      await tester.pumpAndSettle();

      expect(chips(tester), ['전체 기간', '이번 달*', '이번 주']);
      expect(stats(tester), [('참여 러너', '0명'), ('1위 기록', '—'), ('평균 기록', '—')]);
      final me = myRank(tester);
      expect([me.rank, me.meta, me.value], ['—', '이번 달 완주 기록이 없어요', '—']);
      expect(text('이번 달에 완주한 러너가 아직 없어요'), findsOneWidget);
      expect(find.byType(WdRankList), findsNothing);
      expect(find.textContaining('전체 순위'), findsNothing);
      expect(bottomButtons(tester), [('고스트 없음', false), ('이 코스로 달리기', true)],
          reason: '전체 기간에는 달린 러너가 있다');
    });

    testWidgets('turns the ghost off when I am the only finisher', (tester) async {
      rankings.summaries = {
        RankingPeriod.all: courseRankingSummary(
          participants: 1,
          average: 1634,
          me: const {
            'status': 'RANKED',
            'rank': 1,
            'courseElapsedSeconds': 1634,
            'paceSecondsPerKm': 314,
            'completedAt': '2026-09-08T01:00:00Z',
            'topPercent': 100,
          },
          top: [courseRankingEntry(1, '러닝왕김', 1634, pace: 314, mine: true)],
        ),
      };
      await openDetail(tester);
      expect(bottomButtons(tester), [('고스트 없음', false), ('이 코스로 달리기', true)], reason: '내 기록은 고스트가 아니다');

      await tester.tap(text('랭킹'));
      await tester.pumpAndSettle();
      expect([for (final rank in ranks(tester)) rank.name], ['나 (러닝왕김)']);
      expect(text('전체 순위 1명 보기'), findsOneWidget);
    });

    testWidgets('shows private instead of my rank (common 6)', (tester) async {
      rankings.summaries = {
        RankingPeriod.all: allRanking(me: const {
          'status': 'PRIVATE',
          'courseElapsedSeconds': 1634,
          'paceSecondsPerKm': 314,
          'completedAt': '2026-09-08T01:00:00Z',
        }),
      };
      await openRanking(tester);

      final me = myRank(tester);
      expect([me.rank, me.meta, me.value], ['비공개 중', '5′14″/km · 09.08', '27:14']);
    });

    testWidgets('offers to retry with dashes when the ranking cannot be loaded, and turns the ghost off',
        (tester) async {
      rankings.error = const ApiException('NETWORK', '');
      await openDetail(tester);
      expect(bottomButtons(tester), [('이 코스로 달리기', true), ('고스트 대결 ▶', false)], reason: '조회 실패는 비활성');

      await tester.tap(text('랭킹'));
      await tester.pumpAndSettle();
      expect(chips(tester), ['전체 기간*', '이번 달', '이번 주']);
      expect(stats(tester), [('참여 러너', '—'), ('1위 기록', '—'), ('평균 기록', '—')]);
      expect(text(CourseRankingTab.failedMessage), findsOneWidget);

      rankings.error = null;
      await tester.ensureVisible(text('다시 시도'));
      await tester.pumpAndSettle();
      await tester.tap(text('다시 시도'));
      await tester.pumpAndSettle();
      expect(myRank(tester).rank, '24');
      expect(bottomButtons(tester).last, ('고스트 대결 ▶', true));
    });

    testWidgets('pulls to refresh only on the ranking tab and keeps the ranking when it fails', (tester) async {
      await openDetail(tester);
      await pull(tester);
      expect(rankings.summaryRequests, hasLength(1), reason: '정보 탭은 당겨도 받지 않는다');

      await tester.tap(text('랭킹'));
      await tester.pumpAndSettle();
      await pull(tester);
      expect(rankings.summaryRequests, hasLength(2));

      rankings.error = const ApiException('NETWORK', '');
      await pull(tester);
      expect(myRank(tester).rank, '24', reason: '받아 둔 랭킹 그대로');
      expect(text(CourseRankingTab.staleMessage), findsOneWidget);
      expect(bottomButtons(tester).last, ('고스트 대결 ▶', false));

      rankings.error = null;
      await tester.ensureVisible(text('다시 시도'));
      await tester.pumpAndSettle();
      await tester.tap(text('다시 시도'));
      await tester.pumpAndSettle();
      expect(text(CourseRankingTab.staleMessage), findsNothing);
      expect(bottomButtons(tester).last, ('고스트 대결 ▶', true));
      expect(rankings.summaryRequests, hasLength(4));
    });
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
          rankingApiClientProvider.overrideWithValue(rankings),
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

    testWidgets('see all opens the course reviews (G2), and back shows fresh reviews (B8-05)', (tester) async {
      reviews
        ..result = reviewSummary(count: 3, average: 4.7, items: (4.7, 4.4, 4.8, 4.1))
        ..cards = [reviewCard('러닝왕김', mine: true), reviewCard('러너_하늘'), reviewCard('새벽러닝')];
      await openHome(tester);
      await tester.tap(find.byType(CourseListCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('리뷰 3'));
      await tester.pumpAndSettle();

      final seeAll = find.text('리뷰 3개 모두 보기');
      await tester.ensureVisible(seeAll);
      await tester.pumpAndSettle();
      await tester.tap(seeAll);
      await tester.pumpAndSettle();
      expect(find.byType(ReviewListScreen), findsOneWidget);
      expect(reviews.listRequests.last.excludeMine, isTrue, reason: 'G2는 내 리뷰를 따로 보인다');
      final requests = reviews.listRequests.length;

      await tester.tap(find.bySemanticsLabel('뒤로 가기'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewListScreen), findsNothing);
      expect(find.text('항목별 평균'), findsOneWidget, reason: '리뷰 탭 그대로');
      expect(reviews.listRequests, hasLength(requests + 1), reason: 'G2에서 쓰거나 지웠을 수 있어 다시 받는다');
      expect(reviews.listRequests.last.excludeMine, isFalse);
    });

    testWidgets('see all opens the course rankings (G3) with the chosen period (B9-05)', (tester) async {
      rankings
        ..summaries[RankingPeriod.week] = weekRanking
        ..rows[RankingPeriod.week] = weekRanking.top;
      await openHome(tester);
      await tester.tap(find.byType(CourseListCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('랭킹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이번 주'));
      await tester.pumpAndSettle();

      final seeAll = find.text('전체 순위 3명 보기');
      await tester.ensureVisible(seeAll);
      await tester.pumpAndSettle();
      await tester.tap(seeAll);
      await tester.pumpAndSettle();
      final screen = tester.widget<CourseRankingsScreen>(find.byType(CourseRankingsScreen));
      expect((screen.courseId, screen.courseName, screen.period), ('c1', '한강 야경 5K', RankingPeriod.week));
      expect(rankings.entryRequests, [(RankingPeriod.week, null)]);
      expect(find.text('전체 순위 3명'), findsOneWidget);

      await tester.tap(find.widgetWithText(WdFilterChip, '전체 기간'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('뒤로 가기'));
      await tester.pumpAndSettle();
      expect(find.byType(CourseRankingsScreen), findsNothing);
      expect(tester.widget<WdFilterChip>(find.widgetWithText(WdFilterChip, '이번 주')).selected, isTrue,
          reason: 'G3에서 바꾼 기간은 B9에 넘기지 않는다');
    });
  });
}
