import 'dart:io';

import 'package:flutter/services.dart';

/// A boot identity is required for comparisons across process restarts.
class RunClockSample {
  const RunClockSample(this.elapsedMs, this.bootId);
  final int elapsedMs;
  final String? bootId;
  Map<String, dynamic> toJson() => {'elapsedMs': elapsedMs, 'bootId': bootId};
  factory RunClockSample.fromJson(Map<String, dynamic> j) =>
      RunClockSample(j['elapsedMs'] as int, j['bootId'] as String?);
  int? since(RunClockSample saved) =>
      bootId == null ||
          bootId!.isEmpty ||
          bootId != saved.bootId ||
          elapsedMs < saved.elapsedMs
      ? null
      : elapsedMs - saved.elapsedMs;
}

class RunRecoveryAnchor {
  const RunRecoveryAnchor(this.bootId, this.originMs, this.checkpointClockMs);
  final String bootId;
  final int originMs, checkpointClockMs;
  Map<String, dynamic> toJson() => {
    'bootId': bootId,
    'originMs': originMs,
    'checkpointClockMs': checkpointClockMs,
  };
  factory RunRecoveryAnchor.fromJson(Map<String, dynamic> j) =>
      RunRecoveryAnchor(
        j['bootId'] as String,
        j['originMs'] as int,
        j['checkpointClockMs'] as int,
      );
  RunRecoveryAnchor at(int ms) =>
      RunRecoveryAnchor(bootId, originMs, originMs + ms);
}

/// Duration measurement uses the OS clock, independent of GPS and wall time.
class MonotonicClock {
  MonotonicClock({bool? android}) : _android = android ?? Platform.isAndroid;
  final bool _android;
  static const _channel = MethodChannel('com.wadadak.app/run_clock');
  final Stopwatch _fallback = Stopwatch()..start();
  Future<int> nowMs() async => _android
      ? (await _channel.invokeMethod<int>('elapsedRealtime'))!
      : _fallback.elapsedMilliseconds;

  Future<RunClockSample> sample() async {
    if (!_android) return RunClockSample(await nowMs(), null);
    final value = await _channel.invokeMapMethod<String, Object?>('snapshot');
    if (value == null) throw StateError('기기 시계를 확인할 수 없어요.');
    return RunClockSample(
      value['elapsedMs'] as int,
      value['bootId'] as String?,
    );
  }
}
