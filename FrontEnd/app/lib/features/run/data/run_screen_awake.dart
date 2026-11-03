import 'dart:io';

import 'package:flutter/services.dart';

/// Screen policy only; it neither wakes a locked phone nor changes GPS tracking.
class RunScreenAwake {
  RunScreenAwake({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('com.wadadak.app/run_screen'),
      _supported = supported ?? Platform.isAndroid;
  final MethodChannel _channel;
  final bool _supported;
  Future<void> setEnabled(bool enabled) async {
    if (_supported) {
      await _channel.invokeMethod<void>('setKeepScreenOn', {
        'enabled': enabled,
      });
    }
  }

  Future<void> close() => setEnabled(false);
}
