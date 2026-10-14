import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'run_location.dart';

/// Android implementation uses the existing running foreground service and wake lock.
class RunDevice {
  static const _channel = MethodChannel('com.wadadak.app/run_device');
  void Function(String)? onVoiceError;
  bool _listening = false;
  void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'voiceError') {
        onVoiceError?.call('음성 안내를 재생하지 못했어요. 휴대폰 음성 설정과 연결을 확인해 주세요.');
      }
    });
  }

  Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    var status = await Permission.activityRecognition.status;
    if (!status.isGranted) {
      status = await Permission.activityRecognition.request();
    }
    if (!status.isGranted) {
      throw RunSetupException(
        '케이던스 측정을 위해 신체 활동 권한을 허용해 주세요.',
        action: status.isPermanentlyDenied ? RunSetupAction.appSettings : null,
      );
    }
  }

  Future<bool> permissionGranted() async =>
      !Platform.isAndroid ||
      (await Permission.activityRecognition.status).isGranted;
  Future<String> startSteps() async {
    if (!Platform.isAndroid) return '이 기기에서는 센서를 지원하지 않아요';
    try {
      return await _channel.invokeMethod<String>('startSteps') ?? '센서 미지원';
    } on PlatformException {
      return '센서 연결 실패';
    }
  }

  Future<Map<String, dynamic>?> sampleSteps({bool force = false}) async {
    if (!Platform.isAndroid) return null;
    final sample = await _channel.invokeMapMethod<String, dynamic>(
      'sampleSteps',
      {'force': force},
    );
    return sample;
  }

  Future<void> stopSteps() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stopSteps');
  }

  Future<bool> initializeVoice() async {
    if (!Platform.isAndroid) return false;
    _listen();
    try {
      return await _channel
              .invokeMethod<bool>('initializeVoice')
              .timeout(const Duration(seconds: 5)) ??
          false;
    } on Object {
      return false;
    }
  }

  Future<bool> speak(String text) async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('speak', {'text': text}) ?? false;
  }

  Future<void> stopVoice() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stopVoice');
  }

  Future<void> close() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('close');
      _channel.setMethodCallHandler(null);
      _listening = false;
      onVoiceError = null;
    }
  }
}
