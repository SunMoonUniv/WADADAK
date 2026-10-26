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
import 'package:wadadak/features/home/course_filter_screen.dart';
import 'package:wadadak/features/home/course_list_sheet.dart';
import 'package:wadadak/features/home/course_search_screen.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

/// G1 코스 검색(SEA-01~03 · SEA-06 · G1-01~05)과 G6 지역 검색(SEA-04 · SEA-07 · G6-01~02), 정책 문서 제4부 4.1 G1 · G6.
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
    activeRunners: 2,
  );
  final bridge = testCourse('한강 다리 왕복 8K', courseId: 'c2', distanceMeters: 8100, difficulty: Difficulty.hard);
  final hill = testCourse('정릉 오르막 4K', courseId: 'c3');
  const here = GeoPoint(37.5593, 126.9784);

  // G6 지역. 서버처럼 코스가 많은 지역부터다. 장안구는 코스가 하나라 범위가 한 점이다.
  const yeongdeungpo = SearchRegion(
    code: '1156000000',
    name: '영등포구',
    count: 12,
    southWest: GeoPoint(37.52, 126.90),
    northEast: GeoPoint(37.53, 126.93),
  );
  const jung = SearchRegion(
    code: '1114000000',
    name: '서울특별시 중구',
    count: 3,
    southWest: GeoPoint(37.55, 126.96),
    northEast: GeoPoint(37.57, 127.02),
  );
  const suwon = SearchRegion(
    code: '4111100000',
    name: '수원시 장안구',
    count: 1,
    southWest: GeoPoint(37.30, 127.01),
    northEast: GeoPoint(37.30, 127.01),
  );
  const regions = [yeongdeungpo, jung, suwon];

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
    expect(courses.searchRequests.single, (query: '한강', sort: CourseListSort.popular, origin: null, cursor: null));
    expect(find.text('코스 검색 결과 2'), findsOneWidget);
    expect(find.text('인기순 ▾'), findsOneWidget, reason: '처음은 인기순(FIL-01)');
    expect(cards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
    // Figma G1: 한 줄에 거리 · 난이도 · 평점, 아래 줄은 현재 러너 · 코스 유형. 리뷰가 없으면 평점이 빠진다.
    expect(find.text('5.2km · 난이도 중 · ★ 4.6 (128)'), findsOneWidget);
    expect(find.text('8.1km · 난이도 상'), findsOneWidget);
    Finder inCard(Finder card, String text) => find.descendant(of: card, matching: find.text(text));
    final first = find.byType(CourseSearchCard).first, last = find.byType(CourseSearchCard).last;
    expect(inCard(first, '지금 2명 달리는 중'), findsOneWidget);
    expect(inCard(first, '달려서 만든 코스'), findsOneWidget);
    expect(tester.getTopLeft(inCard(first, '지금 2명 달리는 중')).dx, lessThan(tester.getTopLeft(inCard(first, '달려서 만든 코스')).dx));
    expect(inCard(last, '달리는 러너 없음'), findsOneWidget);
    expect(inCard(last, '그려서 만든 코스'), findsOneWidget);
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

  testWidgets('the region tab lists where the query has courses, and the runner tab is not ready yet (G1-02 · SEA-04)',
      (tester) async {
    courses.searchedRegions = regions;
    await openSearch(tester);
    await search(tester, '한강');
    expect(courses.searchRegionRequests, isEmpty, reason: '보이는 탭만 받는다');

    await tap(tester, searchTab('지역'));
    expect(courses.searchRegionRequests, ['한강']);
    expect(find.byType(CourseSearchCard), findsNothing);
    // Figma G6: 머리글 아래 서버 순서(코스가 많은 지역부터) 그대로, 줄마다 오른쪽에 `한강 코스 N개 ›`.
    expect(find.text('‘한강’ 코스가 있는 지역 · 3곳'), findsOneWidget);
    final rows = [for (final region in regions) tester.getRect(find.text(region.name))];
    for (var i = 1; i < rows.length; i++) {
      expect(rows[i].top, greaterThan(rows[i - 1].bottom), reason: '${regions[i].name}은 ${regions[i - 1].name} 아래');
    }
    for (final text in ['한강 코스 12개', '한강 코스 3개', '한강 코스 1개']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('›'), findsNWidgets(3));

    await tap(tester, searchTab('러너'));
    expect(find.text('러너 검색은 준비 중이에요'), findsOneWidget);
    expect(tester.widget<TextField>(input()).controller!.text, '한강');

    await tap(tester, searchTab('코스'));
    expect(cards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
    await tap(tester, searchTab('지역'));
    expect(find.text('영등포구'), findsOneWidget);
    expect(courses.searchRequests, hasLength(1), reason: '탭을 바꿔도 같은 검색어는 다시 받지 않는다');
    expect(courses.searchRegionRequests, hasLength(1));
  });

  testWidgets('each tab loads the last searched query when it shows up (G6-01)', (tester) async {
    courses.searchedRegions = regions;
    await openSearch(tester);
    await tap(tester, searchTab('지역'));
    expect(courses.searchRegionRequests, isEmpty, reason: '검색 전에는 받지 않는다');

    await search(tester, '한강');
    expect(courses.searchRegionRequests, ['한강']);
    expect(courses.searchRequests, isEmpty);
    expect(find.text('‘한강’ 코스가 있는 지역 · 3곳'), findsOneWidget);

    await tap(tester, searchTab('코스'));
    expect(courses.searchRequests.single.query, '한강');
    expect(cards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);

    await search(tester, '정릉');
    await tap(tester, searchTab('지역'));
    expect(courses.searchRegionRequests, ['한강', '정릉']);
    expect(find.text('‘정릉’ 코스가 있는 지역 · 3곳'), findsOneWidget);
    expect(find.text('정릉 코스 12개'), findsOneWidget);
  });

  testWidgets('a query without courses shows G8 on the region tab too (SEA-06)', (tester) async {
    await openSearch(tester);
    await tap(tester, searchTab('지역'));
    await search(tester, '한강숲길');

    expect(find.text('‘한강숲길’ 검색 결과가 없어요'), findsOneWidget);
    expect(find.text(CourseSearchScreen.emptyMessage), findsOneWidget);
    expect(find.byType(WdButton), findsNothing);
    expect(find.textContaining('코스가 있는 지역'), findsNothing);
  });

  testWidgets('a region search that fails can be retried, and a failed refresh keeps the regions (QST-02)',
      (tester) async {
    courses.searchRegionsError = const ApiException('COMMON-500', '서버 오류', status: 500);
    await openSearch(tester);
    await tap(tester, searchTab('지역'));
    await search(tester, '한강');
    expect(find.text(CourseSearchScreen.loadFailedMessage), findsOneWidget);

    courses
      ..searchRegionsError = null
      ..searchedRegions = regions;
    await tap(tester, find.widgetWithText(WdButton, '다시 시도'));
    expect(courses.searchRegionRequests, ['한강', '한강']);
    expect(find.text('영등포구'), findsOneWidget);

    // 같은 검색어를 다시 검색하다 실패하면 전 결과를 두고 알린다.
    courses.searchRegionsError = const ApiException('COMMON-500', '서버 오류', status: 500);
    await search(tester, '한강');
    expect(courses.searchRegionRequests, hasLength(3));
    expect(find.text('영등포구'), findsOneWidget);
    expect(find.text('서버 오류'), findsOneWidget);
  });

  testWidgets('the region tab shows a loading mark, and ✕ drops an answer that comes late', (tester) async {
    courses.searchedRegions = regions;
    await openSearch(tester);
    await tap(tester, searchTab('지역'));
    courses.searchRegionsGate = Completer<void>();
    await tester.enterText(input(), '한강');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tap(tester, find.bySemanticsLabel('검색어 지우기'));
    courses.searchRegionsGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('영등포구'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a screen reader reads a region row as one button', (tester) async {
    final semantics = tester.ensureSemantics();
    courses.searchedRegions = regions;
    await openSearch(tester);
    await tap(tester, searchTab('지역'));
    await search(tester, '한강');
    expect(tester.getSemantics(find.bySemanticsLabel('영등포구 한강 코스 12개')),
        isSemantics(isButton: true, hasTapAction: true));
    semantics.dispose();
  });

  group('picking a region (G6-02 · SEA-07)', () {
    CourseListSheet sheet(WidgetTester tester) => tester.widget<CourseListSheet>(find.byType(CourseListSheet));

    /// 홈 검색창 `← ⌕ 한강 · 영등포구 ✕`의 ←와 ✕.
    Finder back() => find.bySemanticsLabel('지역 검색 결과로 돌아가기');
    Finder clear() => find.bySemanticsLabel('검색 조건 지우기');
    List<String> listCards(WidgetTester tester) =>
        [for (final card in tester.widgetList<CourseListCard>(find.byType(CourseListCard))) card.course.name];

    /// 지금까지 지도가 받은 횟수. 지도는 축척에 따라 코스나 지역별 코스 수를 받는다.
    ({int maps, int regions}) mark() => (maps: courses.mapRequests.length, regions: courses.regionRequests.length);

    /// [since] 뒤 지도 요청들의 G6 조건.
    List<CourseSearchPick?> mapPicksSince(({int maps, int regions}) since) => [
          for (final request in courses.mapRequests.skip(since.maps)) request.pick,
          for (final request in courses.regionRequests.skip(since.regions)) request.pick,
        ];

    /// 검색창을 열어 [query]로 검색하고 지역 탭에서 [region]을 누른다. 이미 고른 조건이 있으면 검색창의 ←로 연다.
    Future<void> pick(WidgetTester tester, SearchRegion region, {String query = '한강'}) async {
      final bar = find.byType(WdSearchBar);
      await tap(tester, bar.evaluate().isEmpty ? back() : bar);
      await tap(tester, searchTab('지역'));
      await search(tester, query);
      await tap(tester, find.text(region.name));
    }

    setUp(() {
      courses
        ..searchedRegions = regions
        ..onMap = [night, bridge, hill]
        ..listed = [night, bridge, hill];
    });

    testWidgets('closes search and shows the query and region on the map and the list together', (tester) async {
      await openHome(tester);
      // 전체 보기(A6)에서 검색해도 지도와 목록이 반씩인 홈(A2)으로 돌아온다.
      await tap(tester, find.text('전체 보기'));
      expect(sheet(tester).stage, SheetStage.full);
      final before = mark();
      final mapTop = tester.getTopLeft(find.byType(MapView)).dy;

      await pick(tester, regions.first);
      expect(find.byType(CourseSearchScreen), findsNothing);
      expect(sheet(tester).stage, SheetStage.half);
      const picked = CourseSearchPick(query: '한강', region: yeongdeungpo);
      expect(sheet(tester).pick, picked);
      expect(courses.listRequests.last.pick, picked);
      expect(mapPicksSince(before), isNotEmpty);
      expect(mapPicksSince(before), everyElement(picked), reason: '지도 · 지역별 코스 수 · 목록이 같은 조건(MAP-07)');
      expect(listCards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
      // 지도를 옮기기 전 범위로는 받지 않는다(잠깐이라도 G6와 다른 수가 보이지 않게).
      for (final request in courses.listRequests.where((request) => request.pick != null)) {
        expect(request.southWest.lat, lessThanOrEqualTo(yeongdeungpo.southWest.lat));
        expect(request.southWest.lng, lessThanOrEqualTo(yeongdeungpo.southWest.lng));
        expect(request.northEast.lat, greaterThanOrEqualTo(yeongdeungpo.northEast.lat));
        expect(request.northEast.lng, greaterThanOrEqualTo(yeongdeungpo.northEast.lng));
      }

      // 검색창이 G6 위쪽 줄처럼 `← ⌕ 한강 · 영등포구 ✕`로 바뀌고 높이는 그대로다(A6-01). 칩 줄은 정렬 · 필터 그대로.
      expect(find.byType(WdSearchBar), findsNothing);
      expect(find.text('한강 · 영등포구'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(MapView)).dy, mapTop, reason: '지도 크기가 그대로');
      expect(find.text('영등포구 ‘한강’ 코스 2'), findsOneWidget, reason: 'G6 줄 `한강 코스 12개`와 같은 말, 수는 지도 범위 안');
      expect(find.widgetWithText(WdFilterChip, '한강 · 영등포구  ✕'), findsNothing);
      expect(
        [for (final chip in tester.widgetList<WdFilterChip>(find.byType(WdFilterChip))) chip.label],
        [...CourseListSort.values.map((sort) => sort.label), null],
      );
    });

    testWidgets('← and the search bar reopen the query on the region tab, and back keeps the pick', (tester) async {
      await openHome(tester);
      await pick(tester, regions.first);
      const picked = CourseSearchPick(query: '한강', region: yeongdeungpo);
      final regionSearches = courses.searchRegionRequests.length, courseSearches = courses.searchRequests.length;

      await tap(tester, back());
      expect(find.byType(CourseSearchScreen), findsOneWidget);
      final field = tester.widget<TextField>(input());
      expect(field.controller!.text, '한강');
      expect(field.autofocus, isFalse, reason: '결과를 보러 왔으니 키보드를 띄우지 않는다');
      expect(tester.widget<WdTabBar>(find.byType(WdTabBar)).controller!.index, 1, reason: '지역 탭');
      expect(courses.searchRegionRequests.skip(regionSearches), ['한강']);
      expect(courses.searchRequests, hasLength(courseSearches), reason: '코스 탭은 열 때 받는다(G6-01)');
      expect(find.text('서울특별시 중구'), findsOneWidget);

      // 그냥 돌아오면 조건 · 목록이 그대로다.
      final lists = courses.listRequests.length;
      await tap(tester, find.bySemanticsLabel('뒤로 가기'));
      expect(sheet(tester).pick, picked);
      expect(find.text('한강 · 영등포구'), findsOneWidget);
      expect(courses.listRequests, hasLength(lists));

      // 글자를 눌러도 같고, 다른 지역을 고르면 그 조건으로 바뀐다.
      await tap(tester, find.text('한강 · 영등포구'));
      expect(tester.widget<TextField>(input()).controller!.text, '한강');
      await tap(tester, find.text('서울특별시 중구'));
      expect(sheet(tester).pick, const CourseSearchPick(query: '한강', region: jung));
      expect(find.text('한강 · 서울특별시 중구'), findsOneWidget);
      expect(courses.listRequests.last.pick, const CourseSearchPick(query: '한강', region: jung));
    });

    testWidgets('a screen reader can press ← and ✕ of the picked search bar', (tester) async {
      final semantics = tester.ensureSemantics();
      await openHome(tester);
      await pick(tester, regions.first);
      for (final finder in [back(), clear()]) {
        expect(tester.getSemantics(finder), isSemantics(isButton: true, hasTapAction: true));
      }
      semantics.dispose();
    });

    testWidgets('fits the map so the region shows above the half sheet, no closer than the home zoom', (tester) async {
      await openHome(tester);

      // 넓은 지역은 다 들어오게 축소한다. 목록 범위는 반 시트 위로 보이는 지도 부분이다.
      await pick(tester, regions[1]);
      final wide = courses.listRequests.last;
      expect(wide.southWest.lat, lessThanOrEqualTo(jung.southWest.lat));
      expect(wide.southWest.lng, lessThanOrEqualTo(jung.southWest.lng));
      expect(wide.northEast.lat, greaterThanOrEqualTo(jung.northEast.lat));
      expect(wide.northEast.lng, greaterThanOrEqualTo(jung.northEast.lng));
      // 이름표가 출발점 위 가운데에 붙어 양옆에 80(보통 이름표의 반)씩 둔다. 이 지역은 너비에 맞춘다.
      double dp(double lng) => lng / (wide.northEast.lng - wide.southWest.lng) * 402;
      expect(dp(jung.southWest.lng - wide.southWest.lng), closeTo(80, 1));
      expect(dp(wide.northEast.lng - jung.northEast.lng), closeTo(80, 1));
      expect(wide.northEast.lat - jung.northEast.lat, greaterThan(jung.southWest.lat - wide.southWest.lat),
          reason: '위는 이름표 높이만큼 더 둔다');
      expect(listCards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);

      // 코스가 하나뿐인 지역은 그 출발점을 가운데(이름표 자리만큼 조금 아래)에 두고 홈을 여는 줌(축척 200m)보다 확대하지 않는다.
      await pick(tester, regions.last);
      final single = courses.listRequests.last;
      expect((single.southWest.lng + single.northEast.lng) / 2, closeTo(suwon.southWest.lng, 0.0001));
      final above = single.northEast.lat - suwon.southWest.lat, below = suwon.southWest.lat - single.southWest.lat;
      expect(above, greaterThan(below));
      final visible = tester.getTopLeft(find.byType(CourseListSheet)).dy - tester.getTopLeft(find.byType(MapView)).dy;
      expect((above - below) / (above + below) * visible, closeTo(32, 1), reason: '보이는 부분 가운데에서 16 아래');
      expect(single.northEast.lng - single.southWest.lng, closeTo(402 * 360 / (256 * 16384), 0.0005), reason: '줌 14');

      // 이미 그 자리여도 다시 받는다.
      final lists = courses.listRequests.length;
      await pick(tester, regions.last);
      expect(courses.listRequests, hasLength(greaterThan(lists)));
      expect(listCards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
    });

    testWidgets('shows course labels instead of region counts while picked, however far the fit zooms out',
        (tester) async {
      // 다 담으려면 축척 500m보다 넓게 축소하는 넓은 지역.
      const wide = SearchRegion(
        code: '1114000000',
        name: '서울특별시 중구',
        count: 2,
        southWest: GeoPoint(37.55, 126.88),
        northEast: GeoPoint(37.57, 127.08),
      );
      courses
        ..searchedRegions = [wide]
        ..regions = [const RegionCount(code: '1114000000', name: '중구', count: 3, center: GeoPoint(37.56, 126.98))];
      await openHome(tester);
      final before = mark();

      await pick(tester, wide);
      expect(courses.regionRequests.skip(before.regions), isEmpty, reason: '축척 규칙(MAP-02) 대신 코스를 받는다');
      expect(courses.mapRequests.last.pick, const CourseSearchPick(query: '한강', region: wide));
      expect(find.widgetWithText(WdMapCourseLabel, '한강 야경 5K · ★4.6'), findsOneWidget);
      expect(find.byType(WdRegionCountBubble), findsNothing);

      // 조건을 풀면 홈을 여는 자리(축척 200m)로 돌아가 다시 축척대로 보인다.
      await tap(tester, clear());
      expect(courses.mapRequests.last.pick, isNull);
      expect(courses.regionRequests.skip(before.regions), isEmpty);
      expect(find.widgetWithText(WdMapCourseLabel, '정릉 오르막 4K'), findsOneWidget);
    });

    testWidgets('resets the A3 filter and the sort like A3 reset', (tester) async {
      await openHome(tester);
      await tap(tester, find.byWidgetPredicate((widget) => widget is WdFilterChip && widget.icon == WdIcons.sliders));
      final a3 = find.descendant(of: find.byType(CourseFilterScreen), matching: find.byType(Scrollable)).first;
      for (final label in ['상', '최신순']) {
        await tester.scrollUntilVisible(find.widgetWithText(WdFilterChip, label), 100, scrollable: a3);
        await tester.tap(find.widgetWithText(WdFilterChip, label));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tap(tester, find.descendant(of: find.byType(WdBottomBar), matching: find.byType(WdButton)));
      expect(courses.listRequests.last.filter, const CourseFilter(difficulties: {Difficulty.hard}));
      expect(courses.listRequests.last.sort, CourseListSort.latest);

      await pick(tester, regions.first);
      final list = courses.listRequests.last;
      expect(list.filter, CourseFilter.none);
      expect(list.sort, CourseListSort.initial);
      expect(list.period, isNull);
      expect(courses.mapRequests.last.filter, CourseFilter.none);
      expect(listCards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);

      // A3도 G6 조건 안에서 센다.
      await tap(tester, find.byWidgetPredicate((widget) => widget is WdFilterChip && widget.icon == WdIcons.sliders));
      expect(courses.mapRequests.last.pick, const CourseSearchPick(query: '한강', region: yeongdeungpo));
      expect(find.text('코스 2개 보기'), findsOneWidget);
    });

    testWidgets('✕, `필터 초기화` and another bottom tab drop the query and region', (tester) async {
      await openHome(tester);
      final start = courses.listRequests.last;

      // ✕를 누르면 다른 하단 탭에 갔다 온 것처럼 홈을 처음 연 모습이다(FIL-08). 검색창도 처음 모양이다.
      await pick(tester, regions.first);
      await tap(tester, find.widgetWithText(WdFilterChip, '최신순'));
      await tap(tester, find.text('전체 보기'));
      await tap(tester, clear());
      expect(find.text('한강 · 영등포구'), findsNothing);
      expect(find.byType(WdSearchBar), findsOneWidget);
      expect(sheet(tester).stage, SheetStage.half);
      final cleared = courses.listRequests.last;
      expect(cleared.pick, isNull);
      expect(cleared.sort, CourseListSort.initial);
      for (final (actual, expected) in [(cleared.southWest, start.southWest), (cleared.northEast, start.northEast)]) {
        expect(actual.lat, closeTo(expected.lat, 1e-6), reason: '지도는 홈을 여는 자리');
        expect(actual.lng, closeTo(expected.lng, 1e-6), reason: '지도는 홈을 여는 자리');
      }
      expect(find.text('지금 달리기 좋은 코스 3'), findsOneWidget);

      // 걸린 코스가 없으면 필터처럼 `필터 초기화`를 준다(STA-04).
      courses.listed = [hill];
      await pick(tester, regions.first);
      expect(find.text(CourseListSheet.filteredEmptyMessage), findsOneWidget);
      await tap(tester, find.widgetWithText(WdButton, '필터 초기화'));
      expect(find.byType(WdSearchBar), findsOneWidget);
      expect(courses.listRequests.last.pick, isNull);
      expect(listCards(tester), ['정릉 오르막 4K']);

      // 다른 하단 탭으로 떠나면 처음으로 돌아간다(FIL-08).
      courses.listed = [night, bridge, hill];
      await pick(tester, regions.first);
      await tap(tester, bottomTab('랭킹'));
      await tap(tester, bottomTab('홈'));
      expect(find.byType(WdSearchBar), findsOneWidget);
      expect(courses.listRequests.last.pick, isNull);
      expect(sheet(tester).stage, SheetStage.half);
    });

    testWidgets('back from search without picking keeps home as it was', (tester) async {
      await openHome(tester);
      await tap(tester, find.byType(WdSearchBar));
      await tap(tester, searchTab('지역'));
      await search(tester, '한강');
      await tap(tester, find.bySemanticsLabel('뒤로 가기'));

      expect(sheet(tester).stage, SheetStage.half);
      expect(sheet(tester).pick, isNull);
      expect(courses.listRequests.map((request) => request.pick), everyElement(isNull));
    });
  });

  testWidgets('changes the sort like the home list, asking for the location for nearest (G1-03)', (tester) async {
    await openSearch(tester);
    await search(tester, '한강');

    // `인기순 ▾` 바로 아래에 나머지 정렬(FIL-01 순서)이 든 메뉴가 뜨고, 메뉴 안 글자의 왼쪽 끝이 맞는다. 바깥을 누르면 그대로 닫힌다.
    await tap(tester, find.text('인기순 ▾'));
    expect(find.text('인기순'), findsNothing);
    final label = tester.getRect(find.text('인기순 ▾'));
    final rows = [for (final option in ['평점순', '가까운순', '최신순', '실시간순']) tester.getRect(find.text(option))];
    expect(rows.first.top - label.bottom, lessThan(16), reason: '글자 바로 아래');
    for (var i = 0; i < rows.length; i++) {
      final above = i == 0 ? label : rows[i - 1];
      expect(rows[i].top, greaterThan(above.bottom), reason: '위에서부터 FIL-01 순서');
      expect(rows[i].top - above.bottom, rows.first.top - label.bottom, reason: '줄 사이가 모두 같다');
      expect(rows[i].left, label.left);
    }
    final menu = tester.getRect(find.ancestor(of: find.text('가까운순'), matching: find.byType(DecoratedBox)).first);
    expect(menu.top, greaterThan(label.bottom), reason: '메뉴는 `인기순 ▾`을 가리지 않는다');
    expect(menu.left, lessThan(label.left));
    expect(menu.right, greaterThanOrEqualTo(label.right));
    expect(menu.bottom, greaterThan(rows.last.bottom));
    expect(menu.right, lessThanOrEqualTo(tester.view.physicalSize.width / tester.view.devicePixelRatio));
    final nearestText = tester.widget<RichText>(
        find.byWidgetPredicate((widget) => widget is RichText && widget.text.toPlainText() == '가까운순'));
    expect(nearestText.text.style?.decoration, TextDecoration.none, reason: '기본 글씨 모양이 없으면 노란 밑줄이 생긴다');
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.text('가까운순'), findsNothing);
    expect(courses.searchRequests, hasLength(1));

    await tap(tester, find.text('인기순 ▾'));
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
    await tap(tester, find.text('최신순 ▾'));
    await tap(tester, find.text('실시간순'));
    expect(courses.searchRequests.last, (query: '한강', sort: CourseListSort.live, origin: null, cursor: null));

    // 위치를 못 받으면 알리고 정렬을 그대로 둔다.
    final requests = courses.searchRequests.length;
    location.error = const DeviceSetupException('위치 권한이 필요해요.');
    await tap(tester, find.text('실시간순 ▾'));
    await tap(tester, find.text('가까운순'));
    expect(find.text('위치 권한이 필요해요.'), findsOneWidget);
    expect(find.text('실시간순 ▾'), findsOneWidget);
    expect(courses.searchRequests, hasLength(requests));
  });

  testWidgets('a screen reader can press back, clear, the sort and its options', (tester) async {
    final semantics = tester.ensureSemantics();
    await openSearch(tester);
    await search(tester, '한강');
    for (final label in ['뒤로 가기', '검색어 지우기', '정렬 인기순']) {
      expect(tester.getSemantics(find.bySemanticsLabel(label)), isSemantics(isButton: true, hasTapAction: true),
          reason: label);
    }
    await tap(tester, find.text('인기순 ▾'));
    for (final label in ['평점순', '가까운순', '최신순', '실시간순']) {
      expect(tester.getSemantics(find.bySemanticsLabel(label)), isSemantics(isButton: true, hasTapAction: true),
          reason: label);
    }
    semantics.dispose();
  });

  testWidgets('a sort that fails keeps the results and the sort they were shown with', (tester) async {
    await openSearch(tester);
    await search(tester, '한강');

    courses.searchError = const ApiException('COMMON-500', '서버 오류', status: 500);
    await tap(tester, find.text('인기순 ▾'));
    await tap(tester, find.text('평점순'));

    expect(cards(tester), ['한강 야경 5K', '한강 다리 왕복 8K']);
    expect(find.text('인기순 ▾'), findsOneWidget);
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
    expect(courses.searchRequests.last, (query: '한강', sort: CourseListSort.popular, origin: null, cursor: '5'));
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
