import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wadadak/core/location/location_service.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/features/home/my_location.dart';

/// 마지막 위치 [last]가 있고, 새로 재면 [current]다.
class _Location extends LocationService {
  Position? last;
  int fixes = 0;

  @override
  Future<void> ensurePermission({bool precise = false}) async {}

  @override
  Future<Position?> lastKnownPosition() async => last;

  @override
  Future<Position> currentPosition({LocationSettings? settings}) async {
    fixes++;
    return position(37.5, ago: Duration.zero);
  }
}

Position position(double lat, {required Duration ago, double accuracy = 10}) => Position(
      latitude: lat,
      longitude: 127,
      timestamp: DateTime.now().subtract(ago),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// 가까운순 · 내 위치 버튼의 현재 위치: 최근에 잰 마지막 위치는 바로 쓰고, 아니면 새로 잰다.
void main() {
  late _Location service;
  late MyLocation location;

  setUp(() {
    service = _Location();
    location = MyLocation(service);
  });

  test('uses the last location measured within 5 minutes within 150 m without a new fix', () async {
    service.last = position(37.4, ago: const Duration(minutes: 4), accuracy: 140);

    expect(await location.request(), const GeoPoint(37.4, 127));
    expect(service.fixes, 0);
  });

  test('measures again when the last location is old, rough or missing', () async {
    for (final last in [
      position(37.4, ago: const Duration(minutes: 6)),
      position(37.4, ago: const Duration(seconds: 30), accuracy: 200),
      null,
    ]) {
      service.last = last;
      expect(await location.request(), const GeoPoint(37.5, 127));
    }
    expect(service.fixes, 3);
  });
}
