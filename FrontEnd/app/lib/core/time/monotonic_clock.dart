import 'dart:io';

import 'package:flutter/services.dart';

/// Duration measurement uses the OS clock, independent of GPS and wall time.
class MonotonicClock {
  static const _channel = MethodChannel('com.wadadak.app/run_clock');
  final Stopwatch _fallback = Stopwatch()..start();
  Future<int> nowMs() async => Platform.isAndroid
      ? (await _channel.invokeMethod<int>('elapsedRealtime'))!
      : _fallback.elapsedMilliseconds;
}
