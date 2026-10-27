import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.wadadak.app/run_clock');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('Android snapshot retains the OS elapsed time and boot identity across clock instances', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'snapshot'
              ? {'elapsedMs': 456789, 'bootId': 'android.boot:23'}
              : 456789;
        });
    final first = await MonotonicClock(android: true).sample();
    final second = await MonotonicClock(android: true).sample();
    expect(first.elapsedMs, 456789);
    expect(second.since(first), 0);
    expect(await MonotonicClock(android: true).nowMs(), 456789);
    expect(calls, ['snapshot', 'snapshot', 'elapsedRealtime']);
  });
  test(
    'fallback, unknown boot and clock rollback cannot prove a restart interval',
    () async {
      final first = await MonotonicClock(android: false).sample();
      expect(
        (await MonotonicClock(android: false).sample()).since(first),
        isNull,
      );
      expect(
        const RunClockSample(10, 'b').since(const RunClockSample(5, 'a')),
        isNull,
      );
      expect(
        const RunClockSample(10, 'a').since(const RunClockSample(11, 'a')),
        isNull,
      );
      expect(
        const RunClockSample(10, null).since(const RunClockSample(5, null)),
        isNull,
      );
    },
  );
}
