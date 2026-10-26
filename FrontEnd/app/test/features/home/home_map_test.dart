import 'dart:math' as math;

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
import 'package:wadadak/features/home/course_list_sheet.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseApi courses;
  late FakeMyLocation location;

  final seongbukcheon = testCourse(
    '성북천 벚꽃길 3K',
    courseId: 'c1',
    route: const [GeoPoint(37.5666, 126.9784), GeoPoint(37.5700, 126.9800)],
  );
  final jeongneung = testCourse(
    '정릉 오르막 4K',
    courseId: 'c2',
    route: const [GeoPoint(37.5680, 126.9760), GeoPoint(37.5720, 126.9750)],
  );
  const seongbuk = RegionCount(code: '1129000000', name: '성북구', count: 1240, center: GeoPoint(37.5894, 127.0167));
  const mapo = RegionCount(code: '1144000000', name: '마포구', count: 3, center: GeoPoint(37.5663, 126.9019));
  const failedMessage = '코스를 불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.';

  /// 로그인한 채로 홈을 연다. 지도는 처음 뜰 때 한 번 범위 안 코스를 받는다.
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

  /// 목록 시트 위쪽 지도를 끈다.
  Future<void> moveMap(WidgetTester tester) async {
    await tester.dragFrom(const Offset(200, 150), const Offset(-120, 0));
    await tester.pumpAndSettle();
  }

  /// 시청을 가운데 두고 [zoom]으로 확대 · 축소한다. 시청 근처에서 줌 13은 축척 500m, 12는 1km, 10은 2km, 9는 5km다.
  Future<void> zoomTo(WidgetTester tester, double zoom) async {
    await (tester.state(find.byType(DevMapView)) as MapController).moveTo(MapView.seoulCityHall, zoom: zoom);
    await tester.pumpAndSettle();
  }

  MapView map(WidgetTester tester) => tester.widget<MapView>(find.byType(MapView));

  setUp(() {
    courses = FakeCourseApi();
    location = FakeMyLocation();
  });

  testWidgets('draws the courses in the map area with a name label at each start', (tester) async {
    courses.onMap = [seongbukcheon, jeongneung];
    await openHome(tester);

    expect(find.widgetWithText(WdMapCourseLabel, '성북천 벚꽃길 3K'), findsOneWidget);
    expect(find.widgetWithText(WdMapCourseLabel, '정릉 오르막 4K'), findsOneWidget);
    expect([for (final line in map(tester).lines) line.points], [seongbukcheon.route, jeongneung.route]);
    final labels = map(tester).markers;
    expect([for (final label in labels) label.position], [seongbukcheon.route.first, jeongneung.route.first]);
    expect(labels.every((label) => label.anchor == MapMarker.bottom), isTrue, reason: '이름표 아래 가운데가 출발점');

    // 지금 보이는 범위로 물었다(처음 위치는 시청).
    final area = courses.mapRequests.single;
    expect(area.southWest.lat, lessThan(MapView.seoulCityHall.lat));
    expect(area.northEast.lat, greaterThan(MapView.seoulCityHall.lat));
    expect(area.southWest.lng, lessThan(MapView.seoulCityHall.lng));
    expect(area.northEast.lng, greaterThan(MapView.seoulCityHall.lng));
  });

  testWidgets('adds the rating to the name label when the course has reviews (Figma A5)', (tester) async {
    courses.onMap = [
      testCourse('한강 야경 5K', courseId: 'r1', averageRating: 4.6, reviewCount: 128),
      jeongneung,
    ];
    await openHome(tester);

    expect(find.widgetWithText(WdMapCourseLabel, '한강 야경 5K · ★4.6'), findsOneWidget);
    expect(find.widgetWithText(WdMapCourseLabel, '정릉 오르막 4K'), findsOneWidget, reason: '리뷰가 없으면 이름만');
  });

  testWidgets('puts the more popular course on top and hides the labels it covers (MAP-03)', (tester) async {
    // 서버가 인기순으로 준다. 정릉이 더 인기 있다.
    courses
      ..onMap = [jeongneung, seongbukcheon]
      ..regions = [seongbuk, mapo];
    await openHome(tester);

    expect([for (final line in map(tester).lines) (line.id, line.priority)], [('course-c2', 2), ('course-c1', 1)],
        reason: '인기 있는 코스 경로가 위에 그려진다');
    expect(
      [for (final label in map(tester).markers) (label.id, label.priority, label.hideWhenCollided)],
      [('course-c2', 2, true), ('course-c1', 1, true)],
      reason: '이름표가 겹치면 인기 있는 코스 이름표만 보인다',
    );

    // 지역별 배지는 겹쳐도 숨기지 않는다.
    await zoomTo(tester, 12);
    expect(map(tester).markers, isNotEmpty);
    expect(map(tester).markers.any((badge) => badge.hideWhenCollided), isFalse);
  });

  testWidgets('waits with the current runners while another bottom tab is shown (공통 7)', (tester) async {
    courses
      ..onMap = [seongbukcheon]
      ..listed = [seongbukcheon];
    await openHome(tester);

    await tester.tap(find.descendant(of: find.byType(WdBottomNav), matching: find.text('MY')));
    await tester.pumpAndSettle();
    await tester.pump(CourseListSheet.runnersRefreshInterval);
    await tester.pump();
    expect(courses.runnerRequests, isEmpty);

    // 목록은 탭을 떠날 때 처음부터 다시 받아 두었다(FIL-08). 돌아오면 그사이 지난 1분 몫을 바로 묻는다.
    await tester.tap(find.descendant(of: find.byType(WdBottomNav), matching: find.text('홈')));
    await tester.pumpAndSettle();
    expect(courses.runnerRequests.single, ['c1']);
  });

  testWidgets('loads again for the new area when the map stops moving', (tester) async {
    courses.onMap = [seongbukcheon];
    await openHome(tester);

    courses.onMap = [jeongneung];
    await moveMap(tester);

    expect(find.text('성북천 벚꽃길 3K'), findsNothing);
    expect(find.widgetWithText(WdMapCourseLabel, '정릉 오르막 4K'), findsOneWidget);
    final [first, second] = courses.mapRequests;
    expect(second.southWest.lng, greaterThan(first.southWest.lng), reason: '지도를 왼쪽으로 끌면 동쪽을 본다');
  });

  testWidgets('tells when the courses cannot be loaded at first, and retries', (tester) async {
    courses.mapError = const ApiException(ApiException.network, '네트워크에 연결할 수 없어요.');
    await openHome(tester);
    expect(find.text(failedMessage), findsOneWidget);

    courses
      ..mapError = null
      ..onMap = [seongbukcheon];
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(WdMapCourseLabel, '성북천 벚꽃길 3K'), findsOneWidget);
  });

  testWidgets('keeps the courses it has when a later load fails', (tester) async {
    courses.onMap = [seongbukcheon];
    await openHome(tester);

    courses.mapError = const ApiException(ApiException.network, '네트워크에 연결할 수 없어요.');
    await moveMap(tester);

    expect(find.widgetWithText(WdMapCourseLabel, '성북천 벚꽃길 3K'), findsOneWidget);
    expect(find.text(failedMessage), findsNothing, reason: '갱신 실패는 알리지 않고 전에 받은 코스를 둔다(QST-02)');
  });

  testWidgets('shows course counts by district once the scale is wider than 500m', (tester) async {
    courses
      ..onMap = [seongbukcheon]
      ..regions = [seongbuk, mapo];
    await openHome(tester);
    expect(courses.regionRequests, isEmpty, reason: '처음 줌 14는 축척 200m라 개별 코스');

    await zoomTo(tester, 13);
    expect(courses.regionRequests, isEmpty, reason: '축척 500m부터 개별 코스(MAP-02)');
    expect(find.widgetWithText(WdMapCourseLabel, '성북천 벚꽃길 3K'), findsOneWidget);

    await zoomTo(tester, 12);
    expect(find.byType(WdMapCourseLabel), findsNothing);
    expect(map(tester).lines, isEmpty);
    expect(find.widgetWithText(WdRegionCountBubble, '성북구'), findsOneWidget);
    expect(find.widgetWithText(WdRegionCountBubble, '1,240'), findsOneWidget);
    expect(find.widgetWithText(WdRegionCountBubble, '마포구'), findsOneWidget);
    // 배지 가운데가 그 지역 코스 출발점들의 가운데(A4-01).
    final bubbles = map(tester).markers;
    expect([for (final bubble in bubbles) bubble.position], [seongbuk.center, mapo.center]);
    expect(bubbles.every((bubble) => bubble.anchor == MapMarker.center), isTrue);

    final request = courses.regionRequests.single;
    expect(request.level, RegionLevel.district);
    expect(request.southWest.lat, lessThan(MapView.seoulCityHall.lat));
    expect(request.northEast.lat, greaterThan(MapView.seoulCityHall.lat));

    // 축척 2km까지는 구 단위.
    await zoomTo(tester, 10);
    expect(courses.regionRequests.last.level, RegionLevel.district);
  });

  testWidgets('shows course counts by city once the scale is wider than 2km', (tester) async {
    courses.regions = [const RegionCount(code: '1100000000', name: '서울', count: 3, center: MapView.seoulCityHall)];
    await openHome(tester);

    await zoomTo(tester, 9);

    expect(courses.regionRequests.single.level, RegionLevel.city);
    expect(find.widgetWithText(WdRegionCountBubble, '서울'), findsOneWidget);
  });

  testWidgets('does not zoom out past a 50km scale', (tester) async {
    await openHome(tester);
    await zoomTo(tester, 6);
    await zoomTo(tester, 3);

    final [..., atSix, atThree] = courses.regionRequests;
    expect(atThree.southWest, atSix.southWest, reason: '줌 6(축척 50km)보다 축소되지 않는다(MAP-02)');
    expect(atThree.northEast, atSix.northEast);
  });

  testWidgets('shows the courses again when zoomed back in to 500m', (tester) async {
    courses
      ..onMap = [seongbukcheon]
      ..regions = [seongbuk];
    await openHome(tester);
    await zoomTo(tester, 12);
    expect(find.byType(WdRegionCountBubble), findsOneWidget);

    await zoomTo(tester, 13);

    expect(find.byType(WdRegionCountBubble), findsNothing);
    expect(find.widgetWithText(WdMapCourseLabel, '성북천 벚꽃길 3K'), findsOneWidget);
    expect([for (final line in map(tester).lines) line.points], [seongbukcheon.route]);
  });

  testWidgets('keeps the counts it has when a later load fails', (tester) async {
    courses.regions = [seongbuk];
    await openHome(tester);
    await zoomTo(tester, 12);

    courses.regionsError = const ApiException(ApiException.network, '네트워크에 연결할 수 없어요.');
    await moveMap(tester);

    expect(courses.regionRequests, hasLength(2));
    expect(find.widgetWithText(WdRegionCountBubble, '성북구'), findsOneWidget);
    expect(find.text(failedMessage), findsNothing, reason: '갱신 실패는 알리지 않고 전에 받은 것을 둔다(QST-02)');
  });

  /// 개발용 지도는 웹 메르카토르라 화면 너비(402)가 덮는 경도가 줌으로 정해진다.
  double lngSpanAt(double zoom) => 402 * 360 / (256 * math.pow(2, zoom));

  double mercator(double lat) => math.log(math.tan(math.pi / 4 + lat * math.pi / 360));

  /// [point]가 시트 위로 보이는 지도 부분(조회 범위 [area])의 한가운데에 있다. 메르카토르라 위도는 메르카토르 y로 잰다.
  void expectInMiddle(({GeoPoint southWest, GeoPoint northEast}) area, GeoPoint point) {
    expect((area.southWest.lng + area.northEast.lng) / 2, closeTo(point.lng, 1e-9), reason: '가로 가운데');
    expect((mercator(area.southWest.lat) + mercator(area.northEast.lat)) / 2, closeTo(mercator(point.lat), 1e-9),
        reason: '시트 위로 보이는 부분의 세로 가운데');
  }

  testWidgets('zooms one level in around a region badge when it is tapped', (tester) async {
    courses
      ..onMap = [seongbukcheon]
      ..regions = [seongbuk];
    await openHome(tester);
    await zoomTo(tester, 9);
    expect(courses.regionRequests.last.level, RegionLevel.city);

    // 시 배지 → 축척 2km(구 단위).
    await tester.tap(find.byType(WdRegionCountBubble));
    await tester.pumpAndSettle();
    final district = courses.regionRequests.last;
    expect(district.level, RegionLevel.district);
    expect(district.northEast.lng - district.southWest.lng, closeTo(lngSpanAt(11), 1e-9));
    expectInMiddle((southWest: district.southWest, northEast: district.northEast), seongbuk.center);

    // 구 배지 → 축척 500m(개별 코스).
    final mapRequests = courses.mapRequests.length;
    await tester.tap(find.byType(WdRegionCountBubble));
    await tester.pumpAndSettle();
    expect(courses.mapRequests, hasLength(mapRequests + 1));
    final area = courses.mapRequests.last;
    expect(area.northEast.lng - area.southWest.lng, closeTo(lngSpanAt(13), 1e-9));
    expectInMiddle((southWest: area.southWest, northEast: area.northEast), seongbuk.center);
    expect(find.byType(WdRegionCountBubble), findsNothing);
    expect(find.widgetWithText(WdMapCourseLabel, '성북천 벚꽃길 3K'), findsOneWidget);
  });

  testWidgets('a district badge fits every course of the district and shows labels there until the map moves',
      (tester) async {
    // 성북구 코스가 지금 범위 밖까지 넓게 있어 다 담으려면 축척 500m보다 넓다. 서버가 구 코스 전체의 출발점 범위를 준다.
    const wide = RegionCount(
      code: '1129000000',
      name: '성북구',
      count: 3,
      center: GeoPoint(37.5700, 126.9900),
      southWest: GeoPoint(37.56, 126.96),
      northEast: GeoPoint(37.59, 127.04),
    );
    courses
      ..onMap = [seongbukcheon]
      ..regions = [wide];
    await openHome(tester);
    await zoomTo(tester, 12);
    expect(courses.regionRequests.last.level, RegionLevel.district);
    final maps = courses.mapRequests.length, regions = courses.regionRequests.length;

    await tester.tap(find.byType(WdRegionCountBubble));
    await tester.pumpAndSettle();
    expect(courses.mapRequests, hasLength(maps + 1), reason: '축척과 상관없이 코스를 받는다');
    expect(courses.regionRequests, hasLength(regions));
    final area = courses.mapRequests.last;
    final span = area.northEast.lng - area.southWest.lng;
    expect(span, greaterThan(lngSpanAt(13)), reason: '다 담으려고 축척 500m보다 넓다');
    // 시트 위로 보이는 지도 부분에 구 코스 범위가 모두 들어온다. 이름표가 잘리지 않게 양옆에 80씩 둔다.
    double dp(double lng) => lng / span * 402;
    expect(dp(wide.southWest!.lng - area.southWest.lng), closeTo(80, 1));
    expect(dp(area.northEast.lng - wide.northEast!.lng), closeTo(80, 1));
    expect(area.southWest.lat, lessThan(wide.southWest!.lat));
    expect(area.northEast.lat, greaterThan(wide.northEast!.lat));
    expect(find.byType(WdRegionCountBubble), findsNothing);
    expect(find.widgetWithText(WdMapCourseLabel, '성북천 벚꽃길 3K'), findsOneWidget);

    // 그 자리에서 시트만 바꾸면 그대로 이름표다.
    await tester.tapAt(const Offset(200, 300));
    await tester.pumpAndSettle();
    expect(courses.regionRequests, hasLength(regions));
    expect(find.widgetWithText(WdMapCourseLabel, '성북천 벚꽃길 3K'), findsOneWidget);

    // 지도를 움직이면 다시 축척대로 구 단위 코스 수다.
    await moveMap(tester);
    expect(courses.regionRequests.last.level, RegionLevel.district);
    expect(find.byType(WdMapCourseLabel), findsNothing);
    expect(find.byType(WdRegionCountBubble), findsOneWidget);
  });

  testWidgets('moves to my location at a 100m scale with the location button', (tester) async {
    const here = GeoPoint(37.5894, 127.0167);
    location.location = here;
    await openHome(tester);
    expect(location.requests, 0, reason: '권한이 없으면 홈을 열 때는 묻지 않는다');

    await tester.tap(find.byType(WdMapLocateButton));
    await tester.pumpAndSettle();

    expect(location.requests, 1, reason: '누르면 권한을 묻고 위치를 받는다(A4-05)');
    final area = courses.mapRequests.last;
    expect(area.northEast.lng - area.southWest.lng, closeTo(lngSpanAt(15), 1e-9), reason: '줌 15는 축척 100m');
    expectInMiddle((southWest: area.southWest, northEast: area.northEast), here);
  });

  testWidgets('puts a tapped badge in the middle of the map above the peek sheet too', (tester) async {
    courses.regions = [seongbuk];
    await openHome(tester);
    await tester.tapAt(const Offset(200, 300));
    await tester.pumpAndSettle();
    await zoomTo(tester, 9);

    await tester.tap(find.byType(WdRegionCountBubble));
    await tester.pumpAndSettle();

    final peek = courses.regionRequests.last;
    expectInMiddle((southWest: peek.southWest, northEast: peek.northEast), seongbuk.center);
  });

  testWidgets('tells what to do and stays when my location is not available', (tester) async {
    location.error = const DeviceSetupException('위치 권한을 허용해 주세요.', action: DeviceSettingsAction.appSettings);
    await openHome(tester);
    final requests = courses.mapRequests.length;

    await tester.tap(find.byType(WdMapLocateButton));
    await tester.pumpAndSettle();

    expect(find.text('위치 권한을 허용해 주세요.'), findsOneWidget);
    expect(courses.mapRequests, hasLength(requests), reason: '지도를 옮기지 않는다');
    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    expect(location.openedSettings, [DeviceSettingsAction.appSettings]);
  });
}
