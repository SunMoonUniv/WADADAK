import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/location/location_service.dart';
import '../../core/map/geo_point.dart';
import '../../core/permissions/device_setup.dart';

/// 홈의 현재 위치. 가까운순(FIL-01)과 카드의 `0.8km 거리`에 쓴다.
/// 공통 [LocationService]로 한 번만 받고, 홈에서 기다리기 길지 않게 10초까지만 기다린다.
class MyLocation {
  MyLocation([LocationService? service]) : _service = service ?? LocationService();

  final LocationService _service;

  /// Android는 달리기처럼 기기 위치(LocationManager)로 받는다. Google 위치 서비스로 받으면 `위치 정확도`를 켜라는
  /// 시스템 창이 홈을 열 때마다 뜬다. 정확도를 낮추면 `위치 정확도`가 꺼진 기기에서 GPS를 쓰지 않아 위치를 못 받는다.
  static final _settings = Platform.isAndroid
      ? AndroidSettings(
          accuracy: LocationAccuracy.high,
          forceLocationManager: true,
          timeLimit: const Duration(seconds: 10),
        )
      : const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10));

  /// 위치 권한이 이미 있으면 현재 위치. 권한이 없거나 못 받으면 null이다. 권한을 묻지 않는다(카드 거리).
  Future<GeoPoint?> ifAllowed() async {
    try {
      final permission = await _service.permission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return null;
      return _point(await _service.currentPosition(settings: _settings));
    } on Exception {
      return null;
    }
  }

  /// 권한을 물어서라도 현재 위치를 받는다(가까운순). 못 받으면 [DeviceSetupException]이다.
  Future<GeoPoint> request() async {
    try {
      return _point(await _service.currentPosition(settings: _settings));
    } on DeviceSetupException {
      rethrow;
    } on Exception {
      throw const DeviceSetupException('현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  /// [DeviceSetupException.action]의 설정 화면을 연다.
  Future<void> openSettings(DeviceSettingsAction action) => _service.openSettings(action);

  static GeoPoint _point(Position position) => GeoPoint(position.latitude, position.longitude);
}

final myLocationProvider = Provider<MyLocation>((ref) => MyLocation());
