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
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

void main() {
  late FakeCourseApi courses;

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

  setUp(() => courses = FakeCourseApi());

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
}
