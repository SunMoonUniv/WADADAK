import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/features/run/presentation/route_preview_map.dart';

class CameraRecorder implements MapController {
  final calls = <List<GeoPoint>>[];
  @override
  Future<void> fitPoints(List<GeoPoint> points) async {
    calls.add(points);
  }

  @override
  Future<void> moveTo(
    GeoPoint center, {
    double? zoom,
    bool animate = true,
  }) async {}
  @override
  void showMyLocation({bool follow = true}) {}
  @override
  void hideMyLocation() {}
}

void main() {
  testWidgets(
    'fits all segments when ready, refits a new route, keeps GPS gaps disconnected',
    (tester) async {
      var segments = [
        [const GeoPoint(37, 127), const GeoPoint(37.05, 127.03)],
        [const GeoPoint(37.08, 127.04), const GeoPoint(37.12, 127.15)],
      ];
      late StateSetter rebuild;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Center(
                  child: SizedBox(
                    width: 320,
                    height: 120,
                    child: RunRoutePreviewMap(segments: segments),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final recorder = CameraRecorder();
      tester.widget<MapView>(find.byType(MapView)).onCreated!(recorder);
      await tester.pump();
      expect(recorder.calls.last, segments.expand((s) => s).toList());
      expect(tester.widget<MapView>(find.byType(MapView)).lines, hasLength(2));
      rebuild(
        () => segments = [
          [const GeoPoint(35, 129), const GeoPoint(35.3, 129.4)],
        ],
      );
      await tester.pumpAndSettle();
      expect(recorder.calls.last, segments.single);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long open and loop routes fit inside short preview in both orientations',
    (tester) async {
      final routes = [
        [const GeoPoint(37, 127), const GeoPoint(37.3, 127.05)],
        [const GeoPoint(37, 127), const GeoPoint(37.02, 127.4)],
        [
          const GeoPoint(37, 127),
          const GeoPoint(37.3, 127.05),
          const GeoPoint(37, 127),
        ],
      ];
      for (final route in routes) {
        MapCamera? camera;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [mapEngineProvider.overrideWithValue(MapEngine.dev)],
            child: MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 272,
                  height: 120,
                  child: RunRoutePreviewMap(
                    key: ValueKey(route),
                    segments: [route],
                    onCameraIdle: (c) => camera = c,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(camera, isNotNull);
        for (final point in route) {
          expect(
            point.lat,
            inInclusiveRange(camera!.southWest.lat, camera!.northEast.lat),
          );
          expect(
            point.lng,
            inInclusiveRange(camera!.southWest.lng, camera!.northEast.lng),
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}
