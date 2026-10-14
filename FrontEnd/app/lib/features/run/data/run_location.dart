import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

enum RunSetupAction { appSettings, locationSettings }

class RunSetupException implements Exception {
  const RunSetupException(this.message, {this.action});
  final String message;
  final RunSetupAction? action;
  @override
  String toString() => message;
}

class RunLocation {
  // Outdoor running should work with Android GPS without Google's accuracy service.
  RunLocation({this.forceLocationManager = true});
  final bool forceLocationManager;
  static const _clock = MethodChannel('com.wadadak.app/run_clock');
  final Stopwatch _fallback = Stopwatch()..start();
  Future<LocationPermission> permission() => Geolocator.checkPermission();
  Future<void> openSettings(RunSetupAction action) async {
    final opened = action == RunSetupAction.appSettings
        ? await Geolocator.openAppSettings()
        : await Geolocator.openLocationSettings();
    if (!opened) {
      throw const RunSetupException(
        '설정을 열지 못했어요. 기기의 설정에서 위치 권한과 서비스를 확인해 주세요.',
      );
    }
  }

  Future<int> nowMs() async => Platform.isAndroid
      ? (await _clock.invokeMethod<int>('elapsedRealtime'))!
      : _fallback.elapsedMilliseconds;
  Future<Position> ready() async {
    if (!Platform.isAndroid) {
      throw const RunSetupException('첫 러닝 버전은 Android에서 사용할 수 있어요.');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const RunSetupException(
        '위치 서비스를 켜 주세요.',
        action: RunSetupAction.locationSettings,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const RunSetupException(
        '설정에서 위치 권한을 허용해 주세요.',
        action: RunSetupAction.appSettings,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const RunSetupException(
        '러닝 기록에 위치 권한이 필요해요.',
        action: RunSetupAction.appSettings,
      );
    }
    if (await Geolocator.getLocationAccuracy() !=
        LocationAccuracyStatus.precise) {
      throw const RunSetupException(
        '설정에서 정확한 위치를 허용해 주세요.',
        action: RunSetupAction.appSettings,
      );
    }
    await permissions.Permission.notification.request();
    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          forceLocationManager: forceLocationManager,
          timeLimit: const Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      throw const RunSetupException(
        'GPS 신호를 찾지 못했어요. 실내에서는 신호가 약할 수 있어요. 탁 트인 야외에서 다시 시도해 주세요.',
      );
    }
    if (!usable(position, DateTime.now().toUtc())) {
      throw const RunSetupException('GPS 신호가 약해요. 탁 트인 곳에서 다시 시도해 주세요.');
    }
    return position;
  }

  static bool fresh(Position p, DateTime now) {
    final age = now.difference(p.timestamp).inMilliseconds;
    return age >= -5000 && age <= 10000;
  }

  static bool usable(Position p, DateTime now) =>
      fresh(p, now) &&
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180 &&
      p.accuracy.isFinite &&
      p.accuracy >= 0 &&
      p.accuracy <= 30;

  Stream<Position> positions() => Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      forceLocationManager: forceLocationManager,
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '와다닥 러닝 기록 중',
        notificationText: '화면을 꺼도 러닝 기록을 저장하고 있어요.',
        notificationChannelName: '러닝 측정',
        enableWakeLock: true,
        setOngoing: true,
      ),
    ),
  );
}
