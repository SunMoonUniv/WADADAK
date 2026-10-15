import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/dev_map_view.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/core/permissions/device_setup.dart';
import 'package:wadadak/features/course/course_format.dart';
import 'package:wadadak/features/home/course_filter_screen.dart';
import 'package:wadadak/features/home/course_list_sheet.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseApi courses;
  late FakeMyLocation location;

  final flat3k = testCourse(
    '평지 3K',
    courseId: 'a',
    distanceMeters: 3000,
    difficulty: Difficulty.easy,
    tags: const [CourseTag.flat],
    courseType: CourseType.custom,
  );
  final hill8k = testCourse(
    '오르막 8K',
    courseId: 'b',
    distanceMeters: 8000,
    difficulty: Difficulty.hard,
    tags: const [CourseTag.uphill, CourseTag.nightLight],
    courseType: CourseType.gps,
  );
  final river25k = testCourse(
    '한강 25K',
    courseId: 'c',
    distanceMeters: 25000,
    difficulty: Difficulty.medium,
    tags: const [CourseTag.flat, CourseTag.riverside],
    courseType: CourseType.gps,
  );

  /// 코스 출발점(시청 근처)에서 남쪽으로 약 800m.
  const here = GeoPoint(37.5593, 126.9784);

  /// 로그인한 채로 홈을 연다. 지도 · 목록에 [flat3k] · [hill8k] · [river25k]가 있다.
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
        myLocationProvider.overrideWithValue(location),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
  }

  Finder chip(String label) => find.widgetWithText(WdFilterChip, label);
  bool selected(WidgetTester tester, Finder chip) => tester.widget<WdFilterChip>(chip).selected;

  /// 목록 칩 줄 끝 슬라이더 아이콘 칩(Figma A2).
  Finder filterChip() => find.byWidgetPredicate((widget) => widget is WdFilterChip && widget.icon == WdIcons.sliders);

  /// A3 아래 `코스 N개 보기`.
  Finder applyButton() => find.descendant(of: find.byType(WdBottomBar), matching: find.byType(WdButton));
  String applyLabel(WidgetTester tester) => tester.widget<WdButton>(applyButton()).label;

  /// 목록 시트 칩 줄 끝 슬라이더 아이콘 칩을 눌러 A3를 연다.
  Future<void> openFilter(WidgetTester tester) async {
    await tester.tap(filterChip());
    await tester.pumpAndSettle();
    expect(find.byType(CourseFilterScreen), findsOneWidget);
  }

  /// 마지막으로 바꾼 뒤 약 300ms가 지나 예상 코스 수를 다시 센다.
  Future<void> waitForCount(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(applyButton());
    await tester.pumpAndSettle();
    expect(find.byType(CourseFilterScreen), findsNothing);
  }

  setUp(() {
    courses = FakeCourseApi()
      ..onMap = [flat3k, hill8k, river25k]
      ..listed = [flat3k, hill8k, river25k];
    location = FakeMyLocation(location: here);
  });

  testWidgets('shows only the conditions that work now and counts the courses in the visible map area', (tester) async {
    await openHome(tester);
    expect([selected(tester, chip('최신순')), selected(tester, chip('가까운순')), selected(tester, filterChip())], [true, false, false]);
    expect(find.widgetWithText(WdFilterChip, '필터'), findsNothing, reason: 'Figma A2처럼 글자 대신 슬라이더 아이콘');
    final home = courses.mapRequests.last;

    await openFilter(tester);

    for (final title in ['정렬', '거리', '난이도', '코스 태그', '코스 유형']) {
      expect(find.text(title), findsOneWidget);
    }
    // 코스 통계(F11) 뒤에 붙는 것은 숨긴다.
    for (final hidden in ['인기순', '평점순', '실시간순', '최소 평점', '★4.0+', '1개월']) {
      expect(find.text(hidden), findsNothing);
    }
    expect(selected(tester, chip('최신순')), isTrue);
    expect(find.text('1 km  ~  20 km+'), findsOneWidget);
    expect(applyLabel(tester), '코스 3개 보기');
    final count = courses.mapRequests.last;
    expect((count.southWest, count.northEast), (home.southWest, home.northEast), reason: '홈에 보이는 지도 범위로 센다');
    expect(count.filter.isNone, isTrue);
  });

  testWidgets('counts again about 300ms after the last change and applies only with the button', (tester) async {
    await openHome(tester);
    await openFilter(tester);
    final before = courses.mapRequests.length;

    await tester.tap(chip('상'));
    await tester.pump();
    await tester.tap(chip('하'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(courses.mapRequests, hasLength(before), reason: '바꾸는 동안은 세지 않는다');
    await waitForCount(tester);
    expect(courses.mapRequests, hasLength(before + 1), reason: '마지막 변경 약 300ms 뒤 한 번');
    expect(courses.mapRequests.last.filter, const CourseFilter(difficulties: {Difficulty.hard, Difficulty.easy}));
    expect(applyLabel(tester), '코스 2개 보기');

    await apply(tester);

    const filter = CourseFilter(difficulties: {Difficulty.easy, Difficulty.hard});
    expect(courses.mapRequests.last.filter, filter, reason: '지도에도 같은 조건(A2-04)');
    expect(courses.listRequests.last.filter, filter);
    expect(find.text('지금 달리기 좋은 코스 2'), findsOneWidget);
    expect(find.text('한강 25K'), findsNothing);
    expect(find.text('평지 3K'), findsWidgets);
    expect(selected(tester, filterChip()), isTrue, reason: '조건이 걸려 있다');
  });

  testWidgets('drops the changes when going back', (tester) async {
    await openHome(tester);
    await openFilter(tester);
    await tester.tap(chip('트랙'));
    await waitForCount(tester);

    await tester.tap(find.byWidgetPredicate((widget) => widget is WdIcon && widget.icon == WdIcons.back));
    await tester.pumpAndSettle();

    expect(find.byType(CourseFilterScreen), findsNothing);
    expect(selected(tester, filterChip()), isFalse);
    expect(courses.listRequests.last.filter.isNone, isTrue);
    expect(find.text('지금 달리기 좋은 코스 3'), findsOneWidget);
  });

  testWidgets('keeps the applied conditions when opened again and resets them all with 초기화', (tester) async {
    await openHome(tester);
    await openFilter(tester);
    await tester.tap(chip('평지'));
    await tester.tap(chip('그려서 만든 코스'));
    await waitForCount(tester);
    await apply(tester);

    await openFilter(tester);
    expect(selected(tester, chip('평지')), isTrue, reason: 'A3를 다시 열어도 걸린 조건 그대로(FIL-08)');
    expect(applyLabel(tester), '코스 1개 보기');

    await tester.tap(find.text('초기화'));
    await waitForCount(tester);

    expect(selected(tester, chip('평지')), isFalse);
    expect(selected(tester, chip('전체').last), isTrue, reason: '코스 유형 전체');
    expect(selected(tester, chip('최신순')), isTrue);
    expect(courses.mapRequests.last.filter.isNone, isTrue, reason: '기본 조건으로 다시 센다(A3-05)');
    expect(applyLabel(tester), '코스 3개 보기');
    expect(courses.listRequests.last.filter, isNot(CourseFilter.none), reason: '버튼을 누르기 전에는 홈에 적용하지 않는다');

    await apply(tester);
    expect(courses.listRequests.last.filter.isNone, isTrue);
    expect(selected(tester, filterChip()), isFalse);
  });

  testWidgets('filters by distance with the slider; the far end is 20km+ with no upper bound', (tester) async {
    await openHome(tester);
    await openFilter(tester);
    // 핸들 가운데가 트랙 양 끝이다. 1 · 5 · 10 · 20km+가 같은 간격이다.
    final slider = tester.getRect(find.byType(RangeSlider));
    final left = slider.left + 8, width = slider.width - 16, y = slider.center.dy;

    // 최소를 3km(1~5km 구간의 가운데)로.
    await tester.dragFrom(Offset(left, y), Offset(width / 6, 0));
    await waitForCount(tester);
    expect(find.text('3 km  ~  20 km+'), findsOneWidget);
    expect(find.text('5′30″/km 기준 약 17 ~ 110분+ 코스'), findsOneWidget);
    expect(courses.mapRequests.last.filter, const CourseFilter(minDistanceMeters: 3000), reason: '20km+는 상한 없음');
    expect(applyLabel(tester), '코스 3개 보기');

    // 최대를 8km로. 양 끝을 포함한다(FIL-02).
    await tester.dragFrom(Offset(left + width, y), Offset(-width * (1 - (1 / 3 + 0.6 / 3)), 0));
    await waitForCount(tester);
    expect(find.text('3 km  ~  8 km'), findsOneWidget);
    expect(find.text('5′30″/km 기준 약 17 ~ 44분 코스'), findsOneWidget);
    expect(courses.mapRequests.last.filter, const CourseFilter(minDistanceMeters: 3000, maxDistanceMeters: 8000));
    expect(applyLabel(tester), '코스 2개 보기');
  });

  testWidgets('picks difficulties with 전체, every chosen tag, and one course type', (tester) async {
    await openHome(tester);
    await openFilter(tester);
    final allDifficulties = chip('전체').first, allTypes = chip('전체').last;

    // 난이도: 하나를 고르면 `전체`가 풀리고, 모두 풀면 `전체`로 돌아간다(FIL-03).
    expect(selected(tester, allDifficulties), isTrue);
    await tester.tap(chip('하'));
    await tester.pump();
    expect([selected(tester, allDifficulties), selected(tester, chip('하'))], [false, true]);
    await tester.tap(chip('하'));
    await tester.pump();
    expect(selected(tester, allDifficulties), isTrue);
    await tester.tap(chip('중'));
    await tester.tap(allDifficulties);
    await tester.pump();
    expect([selected(tester, allDifficulties), selected(tester, chip('중'))], [true, false]);

    // 코스 태그: 모두 가진 코스만(FIL-04).
    await tester.tap(chip('오르막'));
    await tester.tap(chip('야간 조명'));
    // 코스 유형: 하나만(FIL-05).
    await tester.tap(chip('그려서 만든 코스'));
    await tester.tap(chip('달려서 만든 코스'));
    await waitForCount(tester);

    expect([selected(tester, allTypes), selected(tester, chip('그려서 만든 코스'))], [false, false]);
    expect(courses.mapRequests.last.filter,
        const CourseFilter(tags: {CourseTag.uphill, CourseTag.nightLight}, courseType: CourseType.gps));
    expect(applyLabel(tester), '코스 1개 보기');
  });

  testWidgets('tells when the courses cannot be counted, and retries', (tester) async {
    await openHome(tester);
    await openFilter(tester);

    courses.mapError = const ApiException(ApiException.network, '네트워크에 연결할 수 없어요.');
    await tester.tap(chip('하'));
    await waitForCount(tester);
    expect(find.text(CourseFilterScreen.countFailedMessage), findsOneWidget);
    expect(applyLabel(tester), '코스 보기');

    courses.mapError = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(applyLabel(tester), '코스 1개 보기');
  });

  testWidgets('sorts by the nearest after getting the location, and shows how far each start is', (tester) async {
    await openHome(tester);
    expect(find.textContaining('km 거리'), findsNothing, reason: '위치 권한이 없으면 묻지 않고 거리를 숨긴다');
    expect(location.requests, 0);

    await tester.tap(chip('가까운순'));
    await tester.pumpAndSettle();

    expect(location.requests, 1, reason: '가까운순을 고를 때 위치를 받는다');
    expect([selected(tester, chip('최신순')), selected(tester, chip('가까운순'))], [false, true]);
    final list = courses.listRequests.last;
    expect(list.sort, CourseListSort.nearest);
    expect(list.origin, here);
    expect(find.text(formatAway(here.distanceTo(flat3k.route.first).round())), findsWidgets);
    expect(find.text('0.8km 거리'), findsWidgets);

    // 최신순으로 돌아가도 거리는 보인다(권한이 있다). 현재 위치는 보내지 않는다.
    await tester.tap(chip('최신순'));
    await tester.pumpAndSettle();
    expect(courses.listRequests.last.sort, CourseListSort.latest);
    expect(courses.listRequests.last.origin, isNull);
    expect(find.text('0.8km 거리'), findsWidgets);
  });

  testWidgets('shows how far each start is when the location is already allowed', (tester) async {
    location.allowed = true;
    await openHome(tester);

    expect(find.text('0.8km 거리'), findsWidgets);
    expect(location.requests, 0, reason: '권한을 묻지 않는다');
    expect(courses.listRequests.last.sort, CourseListSort.latest);
  });

  testWidgets('keeps the sort and tells what to do when the location is not available', (tester) async {
    location.error = const DeviceSetupException('위치 권한을 허용해 주세요.', action: DeviceSettingsAction.appSettings);
    await openHome(tester);

    await tester.tap(chip('가까운순'));
    await tester.pumpAndSettle();

    expect(selected(tester, chip('최신순')), isTrue, reason: '정렬은 그대로');
    expect(courses.listRequests.every((request) => request.sort == CourseListSort.latest), isTrue);
    expect(find.text('위치 권한을 허용해 주세요.'), findsOneWidget);
    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    expect(location.openedSettings, [DeviceSettingsAction.appSettings]);

    // A3에서 가까운순과 조건을 함께 고르면 조건만 적용한다.
    await openFilter(tester);
    await tester.tap(chip('가까운순'));
    await tester.tap(chip('평지'));
    await waitForCount(tester);
    await apply(tester);
    expect(courses.listRequests.last.filter, const CourseFilter(tags: {CourseTag.flat}));
    expect(courses.listRequests.last.sort, CourseListSort.latest);
    expect(selected(tester, chip('최신순')), isTrue);
  });

  testWidgets('tells when no course matches the filter and resets it', (tester) async {
    courses
      ..onMap = [flat3k]
      ..listed = [flat3k];
    await openHome(tester);
    await openFilter(tester);
    await tester.tap(chip('상'));
    await waitForCount(tester);
    expect(applyLabel(tester), '코스 0개 보기');
    await apply(tester);

    // 코스가 없는 지역(STA-01)과 다르다(STA-04).
    expect(find.text(CourseListSheet.filteredEmptyMessage), findsOneWidget);
    expect(find.text(CourseListSheet.emptyMessage), findsNothing);
    expect(find.text('지도 범위 넓히기'), findsNothing);

    await tester.tap(find.widgetWithText(WdButton, '필터 초기화'));
    await tester.pumpAndSettle();

    expect(courses.listRequests.last.filter.isNone, isTrue);
    expect(courses.mapRequests.last.filter.isNone, isTrue);
    expect(find.text('평지 3K'), findsWidgets);
    expect(selected(tester, filterChip()), isFalse);
  });

  testWidgets('counts the regions with the same filter when zoomed out', (tester) async {
    await openHome(tester);
    await openFilter(tester);
    await tester.tap(chip('트랙'));
    await waitForCount(tester);
    await apply(tester);

    // 축척 1km(구 단위 코스 수, A4-01).
    await (tester.state(find.byType(DevMapView)) as MapController).moveTo(MapView.seoulCityHall, zoom: 12);
    await tester.pumpAndSettle();

    expect(courses.regionRequests.last.filter, const CourseFilter(tags: {CourseTag.track}));
  });
}
