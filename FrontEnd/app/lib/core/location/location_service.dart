import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../permissions/device_setup.dart';

/// Shared location access. Features supply tracking settings and quality rules.
class LocationService {
  LocationService({this.forceLocationManager = true});
  final bool forceLocationManager;
  bool get supportsBackgroundTracking => Platform.isAndroid;
  Future<LocationPermission> permission() => Geolocator.checkPermission();
  Future<void> openSettings(DeviceSettingsAction action) async {
    final opened = action == DeviceSettingsAction.appSettings
        ? await Geolocator.openAppSettings()
        : await Geolocator.openLocationSettings();
    if (!opened) {
      throw const DeviceSetupException('기기의 설정에서 위치 권한과 서비스를 확인해 주세요.');
    }
  }

  Future<void> ensurePermission({bool precise = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceSetupException(
        '위치 서비스를 켜 주세요.',
        action: DeviceSettingsAction.locationSettings,
      );
    }
    var value = await Geolocator.checkPermission();
    if (value == LocationPermission.denied) {
      value = await Geolocator.requestPermission();
    }
    if (value == LocationPermission.deniedForever ||
        value == LocationPermission.denied) {
      throw const DeviceSetupException(
        '위치 권한을 허용해 주세요.',
        action: DeviceSettingsAction.appSettings,
      );
    }
    if (precise &&
        await Geolocator.getLocationAccuracy() !=
            LocationAccuracyStatus.precise) {
      throw const DeviceSetupException(
        '설정에서 정확한 위치를 허용해 주세요.',
        action: DeviceSettingsAction.appSettings,
      );
    }
  }

  Future<Position> currentPosition({LocationSettings? settings}) async {
    await ensurePermission();
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings:
            settings ??
            (Platform.isAndroid
                ? AndroidSettings(
                    accuracy: LocationAccuracy.high,
                    forceLocationManager: forceLocationManager,
                    timeLimit: const Duration(seconds: 20),
                  )
                : const LocationSettings(
                    accuracy: LocationAccuracy.high,
                    timeLimit: Duration(seconds: 20),
                  )),
      );
    } on TimeoutException {
      throw const DeviceSetupException(
        'GPS 신호를 찾지 못했어요. 실내에서는 신호가 약할 수 있어요. 탁 트인 야외에서 다시 시도해 주세요.',
      );
    }
  }

  /// Last position the device already has, without a new fix. Fast but may be stale; null when there is none.
  Future<Position?> lastKnownPosition() =>
      Geolocator.getLastKnownPosition(forceAndroidLocationManager: forceLocationManager);

  Stream<Position> positions({required LocationSettings settings}) =>
      Geolocator.getPositionStream(locationSettings: settings);
}
