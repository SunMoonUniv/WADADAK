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
import 'package:wadadak/core/permissions/device_setup.dart';
import 'package:wadadak/features/course/course_list_card.dart';
import 'package:wadadak/features/course/detail/course_detail_screen.dart';
import 'package:wadadak/features/home/course_list_sheet.dart';
import 'package:wadadak/features/home/course_search_screen.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

/// G1 코스 검색(SEA-01~03 · SEA-06 · G1-01~05, 정책 문서 제4부 4.1 G1).
void main() {
  late FakeCourseApi courses;
  late FakeMyLocation location;

  const route = [GeoPoint(37.5666, 126.9784), GeoPoint(37.5700, 126.9800)];
  final night = testCourse(
    '한강 야경 5K',
    courseId: 'c1',
    route: route,
    distanceMeters: 5210,
    difficulty: Difficulty.medium,
    courseType: CourseType.gps,
    averageRating: 4.6,
    reviewCount: 128,
  );
  final bridge = testCourse('한강 다리 왕복 8K', courseId: 'c2', distanceMeters: 8100, difficulty: Difficulty.hard);
  final hill = testCourse('정릉 오르막 4K', courseId: 'c3');
  const here = GeoPoint(37.5593, 126.9784);

  /// 로그인한 채로 홈을 연다.
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
        reviewApiClientProvider.overrideWithValue(FakeCourseReviewApi()),
        rankingApiClientProvider.overrideWithValue(FakeCourseRankingApi()),
        myLocationProvider.overrideWithValue(location),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 홈 검색창을 눌러 G1을 연다.
  Future<void> openSearch(WidgetTester tester) async {
    await openHome(tester);
    await tap(tester, find.byType(WdSearchBar));
  }

  Finder input() => find.descendant(of: find.byType(WdSearchHeader), matching: find.byType(TextField));

  /// 검색어를 넣고 키보드의 검색을 누른다.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(input(), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  List<String> cards(WidgetTester tester) =>
      [for (final card in tester.widgetList<CourseSearchCard>(find.byType(CourseSearchCard))) card.course.name];
  Finder bottomTab(String label) => find.descendant(of: find.byType(WdBottomNav), matching: find.text(label));
  Finder searchTab(String label) => find.descendant(of: find.byType(WdTabBar), matching: find.text(label));

  setUp(() {
    courses = FakeCourseApi()
      ..searchable = [night, bridge, hill]
      ..details = {
        'c1': CourseDetail(
          courseId: 'c1',
          name: '한강 야경 5K',
          courseType: CourseType.gps,
          difficulty: Difficulty.medium,
          tags: const [],
          distanceMeters: 5210,
          route: route,
          distanceMarkers: const [],
          expiresAt: DateTime.utc(2026, 11, 13, 14, 59, 59),
        ),
      };
    location = FakeMyLocation(location: here);
  });

  testWidgets('the home search bar opens G1 with an empty input, the tabs and the bottom tabs', (tester) async {
    await openSearch(tester);

    expect(find.byType(CourseSearchScreen), findsOneWidget);
    final field = tester.widget<TextField>(input());
    expect(field.controller!.text, isEmpty, reason: '최근 검색어 없이 빈 입력(SEA-01)');
    expect(field.autofocus, isTrue);
    expect(tester.widget<WdTabBar>(find.byType(WdTabBar)).tabs, ['코스', '지역', '러너'], reason: '탭에 수는 없다(SEA-02)');
    expect(find.byType(WdBottomNav), findsOneWidget, reason: 'Figma G1 하단 탭');
    expect(find.byType(CourseSearchCard), findsNothing);
    expect(courses.searchRequests, isEmpty);

    await tap(tester, find.bySemanticsLabel('뒤로 가기'));
    expect(find.byType(CourseSearchScreen), findsNothing);
    expect(find.byType(CourseListSheet), findsOneWidget);
  });

  testWidgets('searches with two or more letters and shows the Figma G1 cards', (tester) async {
    await openSearch(tester);

    await search(tester, ' 한 ');
    expect(courses.searchRequests, isEmpty, reason: '공백을 빼고 2글자 미만(G1-01)');
    expect(find.text(CourseSearchScreen.tooShortMessage), findsOneWidget);

    await search(tester, '  한강 ');
    expect(courses.searchRequests.single, (query: '한강', sort: CourseListSort.latest, origin: null, cursor: null));
    expect(find.text('코스 검색 결과 2'), findsOneWidget);
    expect(find.text('최신순 ▾'), findsOneWidget);
    expect(cards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
    // Figma G1: 한 줄에 거리 · 난이도 · 평점, 아래 줄은 코스 유형. 리뷰가 없으면 평점이 빠진다.
    expect(find.text('5.2km · 난이도 중 · ★ 4.6 (128)'), findsOneWidget);
    expect(find.text('8.1km · 난이도 상'), findsOneWidget);
    expect(find.descendant(of: find.byType(CourseSearchCard).first, matching: find.text('달려서 만든 코스')), findsOneWidget);
    expect(find.descendant(of: find.byType(CourseSearchCard).last, matching: find.text('그려서 만든 코스')), findsOneWidget);
    expect(find.textContaining('만료'), findsNothing, reason: 'G1 카드에는 만료 표시가 없다');
  });

  testWidgets('no results shows G8 without a create button (SEA-06)', (tester) async {
    await openSearch(tester);
    await search(tester, '한강숲길');

    expect(find.text('‘한강숲길’ 검색 결과가 없어요'), findsOneWidget);
    expect(find.text(CourseSearchScreen.emptyMessage), findsOneWidget);
    expect(find.text('코스 만들기'), findsNothing);
    expect(find.byType(WdButton), findsNothing);
    expect(find.textContaining('코스 검색 결과'), findsNothing);
  });

  testWidgets('✕ clears the query and the results, and typing alone keeps them', (tester) async {
    await openSearch(tester);
    await search(tester, '한강');

    await tester.enterText(input(), '한강 야');
    await tester.pumpAndSettle();
    expect(cards(tester), hasLength(2), reason: '검색을 누르기 전에는 전 결과');

    await tap(tester, find.bySemanticsLabel('검색어 지우기'));
    expect(tester.widget<TextField>(input()).controller!.text, isEmpty);
    expect(find.byType(CourseSearchCard), findsNothing);
    expect(find.textContaining('코스 검색 결과'), findsNothing);
  });

  testWidgets('the region and runner tabs are not ready yet and keep the query (G1-02)', (tester) async {
    await openSearch(tester);
    await search(tester, '한강');

    await tap(tester, searchTab('지역'));
    expect(find.text('지역 검색은 준비 중이에요'), findsOneWidget);
    expect(find.byType(CourseSearchCard), findsNothing);
    await tap(tester, searchTab('러너'));
    expect(find.text('러너 검색은 준비 중이에요'), findsOneWidget);
    expect(tester.widget<TextField>(input()).controller!.text, '한강');

    await tap(tester, searchTab('코스'));
    expect(cards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
    expect(courses.searchRequests, hasLength(1), reason: '탭을 바꿔도 다시 받지 않는다');
  });

  testWidgets('changes the sort like the home list, asking for the location for nearest (G1-03)', (tester) async {
    await openSearch(tester);
    await search(tester, '한강');

    // `최신순 ▾` 바로 아래에 나머지 정렬이 든 메뉴가 뜨고, 메뉴 안 글자의 왼쪽 끝이 맞는다. 바깥을 누르면 그대로 닫힌다.
    await tap(tester, find.text('최신순 ▾'));
    expect(find.text('최신순'), findsNothing);
    final label = tester.getRect(find.text('최신순 ▾'));
    final nearest = tester.getRect(find.text('가까운순')), rating = tester.getRect(find.text('평점순'));
    expect(nearest.top, greaterThan(label.bottom));
    expect(rating.top, greaterThan(nearest.bottom));
    expect(nearest.top - label.bottom, lessThan(16), reason: '글자 바로 아래');
    expect(nearest.top - label.bottom, rating.top - nearest.bottom, reason: '줄 사이가 모두 같다');
    expect(nearest.left, label.left);
    expect(rating.left, label.left);
    final menu = tester.getRect(find.ancestor(of: find.text('가까운순'), matching: find.byType(DecoratedBox)).first);
    expect(menu.top, greaterThan(label.bottom), reason: '메뉴는 `최신순 ▾`을 가리지 않는다');
    expect(menu.left, lessThan(label.left));
    expect(menu.right, greaterThanOrEqualTo(label.right));
    expect(menu.bottom, greaterThan(rating.bottom));
    expect(menu.right, lessThanOrEqualTo(tester.view.physicalSize.width / tester.view.devicePixelRatio));
    final nearestText = tester.widget<RichText>(
        find.byWidgetPredicate((widget) => widget is RichText && widget.text.toPlainText() == '가까운순'));
    expect(nearestText.text.style?.decoration, TextDecoration.none, reason: '기본 글씨 모양이 없으면 노란 밑줄이 생긴다');
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.text('가까운순'), findsNothing);
    expect(courses.searchRequests, hasLength(1));

    await tap(tester, find.text('최신순 ▾'));
    await tap(tester, find.text('평점순'));
    expect(courses.searchRequests.last, (query: '한강', sort: CourseListSort.rating, origin: null, cursor: null));
    expect(find.text('평점순 ▾'), findsOneWidget);

    await tap(tester, find.text('평점순 ▾'));
    await tap(tester, find.text('가까운순'));
    expect(location.requests, 1);
    expect(courses.searchRequests.last, (query: '한강', sort: CourseListSort.nearest, origin: here, cursor: null));
    expect(find.text('가까운순 ▾'), findsOneWidget);

    await tap(tester, find.text('가까운순 ▾'));
    await tap(tester, find.text('최신순'));
    expect(courses.searchRequests.last, (query: '한강', sort: CourseListSort.latest, origin: null, cursor: null));

    // 위치를 못 받으면 알리고 정렬을 그대로 둔다.
    final requests = courses.searchRequests.length;
    location.error = const DeviceSetupException('위치 권한이 필요해요.');
    await tap(tester, find.text('최신순 ▾'));
    await tap(tester, find.text('가까운순'));
    expect(find.text('위치 권한이 필요해요.'), findsOneWidget);
    expect(find.text('최신순 ▾'), findsOneWidget);
    expect(courses.searchRequests, hasLength(requests));
  });

  testWidgets('a screen reader can press back, clear, the sort and its options', (tester) async {
    final semantics = tester.ensureSemantics();
    await openSearch(tester);
    await search(tester, '한강');
    for (final label in ['뒤로 가기', '검색어 지우기', '정렬 최신순']) {
      expect(tester.getSemantics(find.bySemanticsLabel(label)), isSemantics(isButton: true, hasTapAction: true),
          reason: label);
    }
    await tap(tester, find.text('최신순 ▾'));
    for (final label in ['가까운순', '평점순']) {
      expect(tester.getSemantics(find.bySemanticsLabel(label)), isSemantics(isButton: true, hasTapAction: true),
          reason: label);
    }
    semantics.dispose();
  });

  testWidgets('a sort that fails keeps the results and the sort they were shown with', (tester) async {
    await openSearch(tester);
    await search(tester, '한강');

    courses.searchError = const ApiException('COMMON-500', '서버 오류', status: 500);
    await tap(tester, find.text('최신순 ▾'));
    await tap(tester, find.text('평점순'));

    expect(cards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
    expect(find.text('최신순 ▾'), findsOneWidget);
    expect(find.text('서버 오류'), findsOneWidget);
  });

  testWidgets('loads the next page while scrolling, keeping the count', (tester) async {
    courses
      ..searchable = [for (var i = 1; i <= 7; i++) testCourse('한강 코스 $i', courseId: 'h$i')]
      ..searchPageSize = 5;
    await openSearch(tester);
    await search(tester, '한강');
    expect(courses.searchRequests.single.cursor, isNull);
    expect(find.text('코스 검색 결과 7'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(courses.searchRequests.last, (query: '한강', sort: CourseListSort.latest, origin: null, cursor: '5'));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('한강 코스 7'), findsOneWidget);
    expect(courses.searchRequests, hasLength(2), reason: '마지막 쪽 뒤로는 받지 않는다');
  });

  testWidgets('the first search that fails can be retried (QST-02)', (tester) async {
    courses.searchError = const ApiException('COMMON-500', '서버 오류', status: 500);
    await openSearch(tester);
    await search(tester, '한강');
    expect(find.text(CourseSearchScreen.loadFailedMessage), findsOneWidget);

    courses.searchError = null;
    await tap(tester, find.widgetWithText(WdButton, '다시 시도'));
    expect(cards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
  });

  testWidgets('shows a loading mark for a new query, and drops an answer that comes late', (tester) async {
    await openSearch(tester);
    courses.searchGate = Completer<void>();
    await tester.enterText(input(), '정릉');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 받는 동안 지우면 늦게 온 결과를 버린다.
    await tap(tester, find.bySemanticsLabel('검색어 지우기'));
    courses.searchGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CourseSearchCard), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a card opens B1, and back keeps the query and the results (FIL-08)', (tester) async {
    await openSearch(tester);
    await search(tester, '한강');

    await tap(tester, find.byType(CourseSearchCard).first);
    expect(find.byType(CourseDetailScreen), findsOneWidget);
    expect(courses.detailRequests, ['c1']);

    // 기기의 뒤로 가기
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CourseDetailScreen), findsNothing);
    expect(tester.widget<TextField>(input()).controller!.text, '한강');
    expect(cards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
    expect(courses.searchRequests, hasLength(1));
  });

  testWidgets('another bottom tab and back to home closes G1 (FIL-08)', (tester) async {
    await openSearch(tester);
    await search(tester, '한강');

    await tap(tester, bottomTab('랭킹'));
    await tap(tester, bottomTab('홈'));
    expect(find.byType(CourseSearchScreen), findsNothing);
    expect(find.byType(CourseListSheet), findsOneWidget);

    // 다시 열면 빈 입력이다.
    await tap(tester, find.byType(WdSearchBar));
    expect(tester.widget<TextField>(input()).controller!.text, isEmpty);
    expect(find.byType(CourseSearchCard), findsNothing);
  });

  testWidgets('the home tab closes G1 too', (tester) async {
    await openSearch(tester);
    await tap(tester, bottomTab('홈'));
    expect(find.byType(CourseSearchScreen), findsNothing);
    expect(find.byType(CourseListSheet), findsOneWidget);
  });
}
