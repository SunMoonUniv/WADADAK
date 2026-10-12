import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/geo_point.dart';

void main() {
  // 기대값은 서버와 같은 PostGIS 3.5에서 `ST_Length(ST_GeogFromText('LINESTRING(...)'))`로 구했다.
  const cityHall = GeoPoint(37.5666, 126.9784);

  test('distance matches the server on the WGS84 ellipsoid', () {
    expect(cityHall.distanceTo(const GeoPoint(37.4979, 127.0276)), closeTo(8777.766976496589, 0.001));
    // 남북·동서로 거의 1km — 등록 최소 거리 근처에서 앱과 서버 판단이 같아야 한다.
    expect(cityHall.distanceTo(const GeoPoint(37.5756, 126.9784)), closeTo(998.8953876001274, 0.001));
    expect(cityHall.distanceTo(const GeoPoint(37.5666, 126.9897)), closeTo(998.3193799131292, 0.001));
    // 등록 최대 거리 근처, 그보다 먼 거리.
    expect(cityHall.distanceTo(const GeoPoint(36.8151, 127.1139)), closeTo(84265.62259941475, 0.001));
    expect(const GeoPoint(35.1796, 129.0756).distanceTo(const GeoPoint(33.4996, 126.5312)),
        closeTo(299218.8625739672, 0.001));
    expect(cityHall.distanceTo(const GeoPoint(37.56661, 126.97841)), closeTo(1.4185755310280235, 0.001));
    expect(cityHall.distanceTo(cityHall), 0);
  });

  test('path length adds the straight segments in order', () {
    const points = [
      cityHall,
      GeoPoint(37.5700, 126.9800),
      GeoPoint(37.5720, 126.9850),
      GeoPoint(37.5700, 126.9900),
      cityHall,
    ];
    expect(GeoPoint.pathLength(points), closeTo(2483.7308798722406, 0.001));
    expect(GeoPoint.pathLength(const [cityHall]), 0);
    expect(GeoPoint.pathLength(const []), 0);
  });

  test('reads and writes the server JSON', () {
    expect(GeoPoint.fromJson({'lat': 37.5, 'lng': 127}), const GeoPoint(37.5, 127));
    expect(cityHall.toJson(), {'lat': 37.5666, 'lng': 126.9784});
  });
}
