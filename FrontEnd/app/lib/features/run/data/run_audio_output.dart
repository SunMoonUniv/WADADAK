import 'dart:io';

import 'package:flutter/services.dart';

/// Platform TTS adapter. Scheduling and run lifecycle belong to AudioGuide.
class RunAudioOutput {
  RunAudioOutput({
    MethodChannel? channel,
    bool? supported,
  }) : _channel = channel ?? const MethodChannel('com.wadadak.app/audio_guide'),
       _supported = supported ?? Platform.isAndroid;
  final MethodChannel _channel;
  final bool _supported;
  void Function()? onError;
  bool _listening = false;
  bool _speaking = false;
  int _requestId = 0;
  bool get isSpeaking => _speaking;
  Future<bool> initialize() async {
    if (!_supported) return false;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        final arguments = call.arguments;
        if (arguments is! Map || arguments['requestId'] != _requestId) return;
        if (call.method == 'voiceDone' || call.method == 'voiceError') {
          _speaking = false;
        }
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

  Future<bool> speak(String text) async {
    if (!_supported) return false;
    final requestId = ++_requestId;
    _speaking = true;
    try {
      final accepted =
          await _channel.invokeMethod<bool>('speak', {
            'text': text,
            'requestId': requestId,
          }) ??
          false;
      if (!accepted && requestId == _requestId) _speaking = false;
      return accepted;
    } on Object {
      if (requestId == _requestId) _speaking = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    ++_requestId;
    _speaking = false;
    if (_supported) await _channel.invokeMethod<void>('stopVoice');
  }

  Future<void> close() async {
    onError = null;
    if (_listening) _channel.setMethodCallHandler(null);
    if (_supported) await _channel.invokeMethod<void>('close');
  }
}
