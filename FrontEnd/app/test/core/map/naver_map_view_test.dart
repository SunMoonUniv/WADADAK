import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/map/naver_map_view.dart';

void main() {
  test('sends the heading only after it turns 5° and 0.2 s pass (4.1 현재 위치 점 보내기)', () {
    var now = 0;
    final tracker = MapLocationTracker(isOff: () => false, nowMs: () => now);

    expect(tracker.shouldSend(10), isTrue, reason: '처음 방향은 바로 보낸다');
    now = 100;
    expect(tracker.shouldSend(40), isFalse, reason: '0.2초가 안 지났다');
    now = 300;
    expect(tracker.shouldSend(14), isFalse, reason: '5°가 안 돌았다');
    expect(tracker.shouldSend(40), isTrue);
    now = 600;
    expect(tracker.shouldSend(357), isTrue, reason: '40° → 357°는 43° 돈 것이다');
    now = 900;
    expect(tracker.shouldSend(1), isFalse, reason: '357° → 1°는 4°만 돈 것이다');
  });

  test('does not start tracking that was turned off while getting the location (4.1 현재 위치 점 보내기)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('NDefaultMyLocationTracker');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var off = false;
    var turnOffWhileLocating = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestLocationPermission') return 'granted';
      off = turnOffWhileLocating;
      return {'lat': 37.5, 'lng': 127.0};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final tracker = MapLocationTracker(isOff: () => off);

    expect(await tracker.startLocationService(), isNotNull);
    turnOffWhileLocating = true;
    expect(await tracker.startLocationService(), isNull);
  });
}
