import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

void main() {
  late MapController map;
  late List<MapCamera> cameras;
  late List<GeoPoint> taps;

  Future<void> show(WidgetTester tester, {List<MapMarker> markers = const []}) async {
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

    await map.zoomBy(-1);
    expect(cameras.last.zoom, 15);
  });

  testWidgets('fits all points on screen without zooming out further than needed', (tester) async {
    await show(tester);
    const points = [GeoPoint(37.50, 127.00), GeoPoint(37.60, 127.10), GeoPoint(37.55, 126.95)];

    await map.fitPoints(points);
    for (final point in points) {
      expectOnScreen(cameras.last, point);
    }

    await map.zoomBy(1);
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
}
