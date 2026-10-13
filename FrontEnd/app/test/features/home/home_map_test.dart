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

  const seongbukcheon = MapCourse(
    courseId: 'c1',
    name: '성북천 벚꽃길 3K',
    route: [GeoPoint(37.5666, 126.9784), GeoPoint(37.5700, 126.9800)],
  );
  const jeongneung = MapCourse(
    courseId: 'c2',
    name: '정릉 오르막 4K',
    route: [GeoPoint(37.5680, 126.9760), GeoPoint(37.5720, 126.9750)],
  );
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

  Future<void> moveMap(WidgetTester tester) async {
    await tester.drag(find.byType(DevMapView), const Offset(-120, 0));
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
}
