import 'dart:io';

import 'package:flutter/services.dart';

/// Platform TTS adapter. Scheduling and run lifecycle belong to AudioGuide.
class RunAudioOutput {
  static const _channel = MethodChannel('com.wadadak.app/audio_guide');
  void Function()? onError;
  bool _listening = false;
  Future<bool> initialize() async {
    if (!Platform.isAndroid) return false;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'voiceError') onError?.call();
      });
    }
    try {
      return await _channel
              .invokeMethod<bool>('initializeVoice')
              .timeout(const Duration(seconds: 5)) ??
          false;
    } on Object {
      return false;
    }
  }

  Future<bool> speak(String text) async =>
      Platform.isAndroid &&
      (await _channel.invokeMethod<bool>('speak', {'text': text}) ?? false);
  Future<void> stop() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stopVoice');
  }

  Future<void> close() async {
    onError = null;
    if (_listening) _channel.setMethodCallHandler(null);
    if (Platform.isAndroid) await _channel.invokeMethod<void>('close');
  }
}
