import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/dev_map_view.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/home/course_filter_screen.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';
import 'package:wadadak/main.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../fakes.dart';

/// 홈을 여는 자리(앱을 열 때 · 다른 하단 탭에서 돌아올 때)와 탭 전환 초기화(FIL-08).
void main() {
  late FakeCourseApi courses;
  late FakeMyLocation location;

  final cityHall = testCourse('시청 한 바퀴 1K', courseId: 'a', route: const [MapView.seoulCityHall, GeoPoint(37.5700, 126.9800)]);
  final jeongneung = testCourse(
    '정릉 오르막 4K',
    courseId: 'b',
    route: const [GeoPoint(37.5680, 126.9760), GeoPoint(37.5720, 126.9750)],
    courseType: CourseType.gps,
  );

  /// 기기에 남은 마지막 위치(시청 북동쪽)와 지금 위치(시청 남쪽 약 800m).
  const last = GeoPoint(37.5700, 126.9820);
  const here = GeoPoint(37.5593, 126.9784);

  /// 로그인한 채로 홈을 연다. 지도 · 목록에 [cityHall] · [jeongneung]이 있다.
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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> moveMap(WidgetTester tester) async {
    await tester.dragFrom(const Offset(200, 150), const Offset(-120, 0));
    await tester.pumpAndSettle();
  }

  Finder tab(String label) => find.descendant(of: find.byType(WdBottomNav), matching: find.text(label));
  Finder chip(String label) => find.widgetWithText(WdFilterChip, label);
  bool selected(WidgetTester tester, Finder chip) => tester.widget<WdFilterChip>(chip).selected;
  Finder filterChip() => find.byWidgetPredicate((widget) => widget is WdFilterChip && widget.icon == WdIcons.sliders);
  Finder label(String name) => find.widgetWithText(WdMapCourseLabel, name);
  DraggableScrollableController sheet(WidgetTester tester) =>
      tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet)).controller!;

  /// 개발용 지도는 웹 메르카토르라 화면 너비(402)가 덮는 경도가 줌으로 정해진다.
  double lngSpanAt(double zoom) => 402 * 360 / (256 * math.pow(2, zoom));
  double mercator(double lat) => math.log(math.tan(math.pi / 4 + lat * math.pi / 360));

  /// 마지막으로 받은 지도 범위(시트 위로 보이는 지도 부분)의 한가운데에 [point]가 있고 줌이 14(축척 200m)다.
  void expectOpenAt(GeoPoint point) {
    final area = courses.mapRequests.last;
    expect(area.northEast.lng - area.southWest.lng, closeTo(lngSpanAt(14), 1e-9), reason: '줌 14');
    expect((area.southWest.lng + area.northEast.lng) / 2, closeTo(point.lng, 1e-9), reason: '가로 가운데');
    expect((mercator(area.southWest.lat) + mercator(area.northEast.lat)) / 2, closeTo(mercator(point.lat), 1e-9),
        reason: '시트 위로 보이는 부분의 세로 가운데');
  }

  /// A3에서 코스 유형 `그려서 만든 코스`만 걸어 적용한다.
  Future<void> filterDrawnCourses(WidgetTester tester) async {
    await tap(tester, filterChip());
    await tester.tap(chip('그려서 만든 코스'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tap(tester, find.descendant(of: find.byType(WdBottomBar), matching: find.byType(WdButton)));
    expect(find.byType(CourseFilterScreen), findsNothing);
  }

  setUp(() {
    courses = FakeCourseApi()
      ..onMap = [cityHall, jeongneung]
      ..listed = [cityHall, jeongneung];
    location = FakeMyLocation(location: here);
  });

  testWidgets('opens at Seoul City Hall without asking when the location is not allowed', (tester) async {
    await openHome(tester);

    expect(tester.widget<MapView>(find.byType(MapView)).initialCenter, MapView.seoulCityHall);
    expect(courses.mapRequests.last.northEast.lng - courses.mapRequests.last.southWest.lng, closeTo(lngSpanAt(14), 1e-9));
    expect(location.requests, 0, reason: '권한을 묻지 않는다');
  });

  testWidgets('opens at the last known location in the middle of the map above the sheet, then at the current one',
      (tester) async {
    location
      ..allowed = true
      ..last = last
      ..fix = Completer();
    await openHome(tester);

    expectOpenAt(last);

    location.fix!.complete();
    await tester.pumpAndSettle();

    expectOpenAt(here);
    expect(find.text('0.8km 거리'), findsWidgets);
  });

  testWidgets('keeps the map where the user moved it when the current location comes later', (tester) async {
    location
      ..allowed = true
      ..last = last
      ..fix = Completer();
    await openHome(tester);
    await moveMap(tester);
    final moved = courses.mapRequests.last;

    location.fix!.complete();
    await tester.pumpAndSettle();

    expect(courses.mapRequests.last, moved, reason: '움직인 지도를 옮기지 않는다');
    expect(find.text('0.8km 거리'), findsWidgets, reason: '카드 거리는 지금 위치로');
  });

  testWidgets('opens at the current location when the device has no last location', (tester) async {
    location.allowed = true;
    await openHome(tester);

    expectOpenAt(here);
  });

  testWidgets('starts the home over after another bottom tab: filter, sort, map, the chosen course and the sheet',
      (tester) async {
    await openHome(tester);
    final start = courses.mapRequests.last;
    final mapState = tester.state(find.byType(DevMapView));

    await filterDrawnCourses(tester);
    await tap(tester, label('시청 한 바퀴 1K'));
    await moveMap(tester);
    expect(courses.mapRequests.last.northEast.lng, isNot(closeTo(start.northEast.lng, 1e-9)), reason: '지도를 옮겼다');
    expect(tester.widget<WdMapCourseLabel>(label('시청 한 바퀴 1K')).selected, isTrue);
    sheet(tester).jumpTo(1);
    await tester.pumpAndSettle();

    await tap(tester, tab('MY'));
    await tap(tester, tab('홈'));

    expect(selected(tester, filterChip()), isFalse, reason: '필터 초기화');
    expect(selected(tester, chip('최신순')), isTrue);
    final list = courses.listRequests.last;
    expect(list.filter.isNone, isTrue);
    expect(list.sort, CourseListSort.latest);
    final map = courses.mapRequests.last;
    expect(map.filter.isNone, isTrue);
    expect((map.southWest, map.northEast), (start.southWest, start.northEast), reason: '위치 권한이 없으면 서울시청 · 줌 14');
    expect(tester.widget<WdMapCourseLabel>(label('시청 한 바퀴 1K')).selected, isFalse, reason: '고른 코스가 풀린다');
    expect(label('정릉 오르막 4K'), findsOneWidget);
    expect(sheet(tester).size, closeTo(0.5, 1e-9), reason: '시트는 반(A2)');
    expect(tester.state(find.byType(DevMapView)), same(mapState), reason: '지도는 새로 만들지 않고 카메라만 옮긴다');
  });

  testWidgets('goes back to my location after another bottom tab when the location is allowed', (tester) async {
    await openHome(tester);
    await tap(tester, chip('가까운순'));
    await moveMap(tester);

    await tap(tester, tab('MY'));
    await tap(tester, tab('홈'));

    expect(selected(tester, chip('최신순')), isTrue);
    expectOpenAt(here);
  });

  testWidgets('keeps the home as it is when the home tab is tapped again', (tester) async {
    await openHome(tester);
    await filterDrawnCourses(tester);
    await moveMap(tester);
    final requests = courses.mapRequests.length;

    await tap(tester, tab('홈'));

    expect(selected(tester, filterChip()), isTrue);
    expect(courses.mapRequests.length, requests, reason: '홈을 새로 열지 않아 지도도 그 자리 그대로다');
  });
}
