import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/dev_map_view.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

void main() {
  late MapController map;
  late List<MapCamera> cameras;
  late List<GeoPoint> taps;

  Future<void> show(WidgetTester tester, {List<MapMarker> markers = const [], double minZoom = 0}) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
      child: MaterialApp(
        home: MapView(
          lines: const [
            MapLine(id: 'route', points: [GeoPoint(37.56, 126.97), GeoPoint(37.57, 126.98)]),
            MapLine(id: 'one-point', points: [GeoPoint(37.56, 126.97)]),
          ],
          markers: markers,
          minZoom: minZoom,
          onCreated: (controller) => map = controller,
          onTap: taps.add,
          onCameraIdle: cameras.add,
        ),
      ),
    ));
    await tester.pump();
  }

  void expectOnScreen(MapCamera camera, GeoPoint point) {
    expect(point.lat, inInclusiveRange(camera.southWest.lat, camera.northEast.lat));
    expect(point.lng, inInclusiveRange(camera.southWest.lng, camera.northEast.lng));
  }

  setUp(() {
    cameras = [];
    taps = [];
  });

  testWidgets('tapping the map reports the point under the finger', (tester) async {
    await show(tester);

    await tester.tapAt(const Offset(200, 400));
    expect(taps.single.lat, closeTo(MapView.seoulCityHall.lat, 1e-9));
    expect(taps.single.lng, closeTo(MapView.seoulCityHall.lng, 1e-9));

    // 오른쪽은 동쪽(경도 증가), 위쪽은 북쪽(위도 증가)이다.
    await tester.tapAt(const Offset(300, 300));
    expect(taps.last.lng, greaterThan(MapView.seoulCityHall.lng));
    expect(taps.last.lat, greaterThan(MapView.seoulCityHall.lat));
  });

  testWidgets('reports the camera when it first shows and after each move', (tester) async {
    await show(tester);
    expect(cameras.single.center, MapView.seoulCityHall);
    expect(cameras.single.zoom, 14);
    expectOnScreen(cameras.single, MapView.seoulCityHall);

    await map.moveTo(const GeoPoint(37.5, 127.1), zoom: 16);
    expect(cameras.last.center, const GeoPoint(37.5, 127.1));
    expect(cameras.last.zoom, 16);

    // 줌을 주지 않으면 지금 줌을 유지한다.
    await map.moveTo(const GeoPoint(37.51, 127.11));
    expect(cameras.last.center, const GeoPoint(37.51, 127.11));
    expect(cameras.last.zoom, 16);
  });

  testWidgets('does not zoom out past the min zoom', (tester) async {
    await show(tester, minZoom: 6);

    await map.moveTo(MapView.seoulCityHall, zoom: 3);
    expect(cameras.last.zoom, 6);

    // 오므리기도 막는다.
    final first = await tester.startGesture(const Offset(100, 400));
    final second = await tester.startGesture(const Offset(300, 400));
    await first.moveTo(const Offset(190, 400));
    await second.moveTo(const Offset(210, 400));
    await first.up();
    await second.up();
    await tester.pump();
    expect(cameras.last.zoom, 6);
  });

  testWidgets('reports the scale bar the Naver map shows at the same zoom', (tester) async {
    await show(tester);
    // 에뮬레이터의 네이버 지도도 시청 · 줌 14에서 축척 막대가 200m다.
    expect(cameras.single.scaleMeters, 200);

    final scales = <int>[];
    for (final zoom in <double>[13, 12, 11, 10, 9]) {
      await map.moveTo(MapView.seoulCityHall, zoom: zoom);
      scales.add(cameras.last.scaleMeters);
    }
    expect(scales, [500, 1000, 2000, 2000, 5000]);
  });

  testWidgets('fits all points on screen without zooming out further than needed', (tester) async {
    await show(tester);
    const points = [GeoPoint(37.50, 127.00), GeoPoint(37.60, 127.10), GeoPoint(37.55, 126.95)];

    await map.fitPoints(points);
    for (final point in points) {
      expectOnScreen(cameras.last, point);
    }

    // 한 단계 더 확대하면 다 들어가지 않는다.
    await map.moveTo(cameras.last.center, zoom: cameras.last.zoom + 1);
    expect(points.every((point) {
      final camera = cameras.last;
      return point.lat >= camera.southWest.lat &&
          point.lat <= camera.northEast.lat &&
          point.lng >= camera.southWest.lng &&
          point.lng <= camera.northEast.lng;
    }), isFalse);
  });

  testWidgets('places markers at their position and sends their taps to the marker', (tester) async {
    var markerTaps = 0;
    await show(tester, markers: [
      MapMarker(
        id: 'km-1',
        position: MapView.seoulCityHall,
        child: const WdKmMarker('1 km'),
        imageKey: 'km:1',
        onTap: () => markerTaps++,
      ),
      const MapMarker.icon(id: 'point-1', position: GeoPoint(37.57, 126.99), icon: WdIcons.routePoint),
    ]);

    expect(tester.getCenter(find.byType(WdKmMarker)), const Offset(200, 400));
    expect(find.byType(WdIcon), findsOneWidget);

    await tester.tap(find.byType(WdKmMarker));
    expect(markerTaps, 1);
    expect(taps, isEmpty);

    // onTap이 없는 표지는 누름을 지도로 넘긴다.
    await tester.tap(find.byType(WdIcon), warnIfMissed: false);
    expect(taps, hasLength(1));
  });

  testWidgets('follows the app location until the camera moves for another reason', (tester) async {
    final location = ValueNotifier<GeoPoint?>(null);
    addTearDown(location.dispose);
    final following = <bool>[];
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
      child: MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: location,
          builder: (_, value, _) => MapView(
            myLocationSource: MyLocationSource.app,
            myLocation: value,
            onCreated: (controller) => map = controller,
            onCameraIdle: cameras.add,
            onFollowingChanged: following.add,
          ),
        ),
      ),
    ));
    await tester.pump();
    final dot = find.byKey(DevMapView.myLocationKey);

    // 위치가 아직 없으면 기다렸다가 생기면 그리로 간다.
    map.showMyLocation();
    await tester.pump();
    expect(following, [true]);
    expect(dot, findsNothing);
    location.value = const GeoPoint(37.55, 126.99);
    await tester.pump();
    expect(cameras.last.center, location.value);
    expect(tester.getCenter(dot), const Offset(200, 400));

    // 새 위치마다 따라간다.
    location.value = const GeoPoint(37.551, 126.991);
    await tester.pump();
    expect(cameras.last.center, location.value);
    expect(tester.getCenter(dot), const Offset(200, 400));

    // 손으로 끌면 따라가기만 멈춘다. 점은 계속 위치를 따른다.
    await tester.drag(find.byType(MapView), const Offset(0, 100));
    expect(following, [true, false]);
    final moved = cameras.last.center;
    location.value = const GeoPoint(37.552, 126.992);
    await tester.pump();
    expect(cameras.last.center, moved);
    expect(dot, findsOneWidget);
    expect(tester.getCenter(dot), isNot(const Offset(200, 400)));

    // 다시 켜면 현재 위치로 돌아간다.
    map.showMyLocation();
    await tester.pump();
    expect(following, [true, false, true]);
    expect(cameras.last.center, location.value);

    // 코드로 카메라를 옮겨도 꺼진다.
    await map.moveTo(MapView.seoulCityHall);
    expect(following, [true, false, true, false]);

    map.hideMyLocation();
    await tester.pump();
    expect(dot, findsNothing);

    // 따라가지 않고 점만 보일 수도 있다(홈 현재 위치 버튼).
    final camera = cameras.last.center;
    map.showMyLocation(follow: false);
    await tester.pump();
    expect(dot, findsOneWidget);
    expect(following, [true, false, true, false], reason: '따라가기는 꺼진 채');
    location.value = const GeoPoint(37.553, 126.993);
    await tester.pump();
    expect(cameras.last.center, camera, reason: '카메라는 그대로');
    expect(dot, findsOneWidget);
  });
}
