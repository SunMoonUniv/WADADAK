import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/map/geo_point.dart';

/// 홈 밖에서 등록한 코스(D4)의 출발점. 홈이 받으면 지도를 그곳으로 옮기고 비운다(B4-07과 같다).
/// 홈이 연 B3 · B4는 등록한 코스를 결과로 돌려받아 옮기므로 이것을 쓰지 않는다.
final registeredCourseFocusProvider =
    NotifierProvider<RegisteredCourseFocus, GeoPoint?>(RegisteredCourseFocus.new);

class RegisteredCourseFocus extends Notifier<GeoPoint?> {
  @override
  GeoPoint? build() => null;

  /// 홈 지도를 [startPoint]로 옮겨 달라고 한다.
  void show(GeoPoint startPoint) => state = startPoint;

  /// 홈이 옮겼다.
  void done() => state = null;
}
