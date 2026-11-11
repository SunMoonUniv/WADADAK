import 'package:flutter/foundation.dart';

import '../../../core/map/geo_point.dart';

/// B3에서 그리는 중인 경로. 입력점은 임시 작성 데이터라 화면을 떠나면 버린다(정책 공통 3·B3-08).
///
/// 값으로 다룬다: 고칠 때마다 새 [RouteDraft]를 돌려준다.
@immutable
class RouteDraft {
  const RouteDraft() : this._(const [], 0, const [], 0);

  const RouteDraft._(this.points, this.distanceMeters, this._history, this.filledCount);

  /// 입력점 최대 수(정책 B3-01). 서버도 500개를 넘으면 받지 않는다.
  static const maxPoints = 500;

  /// 직접 생성 코스의 거리 범위(m, 정책 공통 3).
  static const minDistanceMeters = 1000;
  static const maxDistanceMeters = 100000;

  /// 찍은 순서대로. 첫 점이 출발, 마지막 점이 도착이다.
  final List<GeoPoint> points;

  /// 점을 순서대로 직선으로 이은 길이(m). 서버와 같은 WGS84 타원체 기준이다.
  final double distanceMeters;

  // 되돌리기로 돌아갈 상태들. 점을 더한 편집은 마지막 점만 빼면 되므로 null, 전체 지우기 · 채우기는 그 전 상태.
  final List<RouteDraft?> _history;

  /// 자동 생성 후보로 채운 앞쪽 점 수(B3 `자동 생성` A4). 0이면 직접 찍은 점만 있다.
  final int filledCount;

  bool get isEmpty => points.isEmpty;

  /// 500개를 찍어 더 찍을 수 없다.
  bool get isFull => points.length >= maxPoints;

  bool get canUndo => _history.isNotEmpty;

  /// 서버와 같이 반올림한 거리(m)로 비교한다.
  bool get withinDistance =>
      distanceMeters.round() >= minDistanceMeters && distanceMeters.round() <= maxDistanceMeters;

  /// 다음 단계(B3-06)로 갈 수 있다: 입력점 2개 이상, 거리 1km 이상 100km 이하.
  bool get canProceed => points.length >= 2 && withinDistance;

  /// 점을 끝에 더한다. [isFull]이면 그대로다.
  RouteDraft add(GeoPoint point) {
    if (isFull) return this;
    final distance = isEmpty ? 0.0 : distanceMeters + points.last.distanceTo(point);
    return RouteDraft._(List.unmodifiable([...points, point]), distance, [..._history, null], filledCount);
  }

  /// 모든 점을 지운다(B3-04). 되돌리기로 되살릴 수 있다.
  RouteDraft clear() => isEmpty ? this : RouteDraft._(const [], 0, [..._history, _withoutHistory], 0);

  /// 고른 자동 생성 후보의 입력점으로 바꾼다(정책 B3-A08). 끝에 이어 찍을 수 있고, 되돌리기 한 번이면 채우기 전으로 돌아간다.
  RouteDraft fill(List<GeoPoint> filled) {
    final kept = List<GeoPoint>.unmodifiable(filled.take(maxPoints));
    return RouteDraft._(kept, GeoPoint.pathLength(kept), [..._history, _withoutHistory], kept.length);
  }

  /// 직전 편집을 취소한다(B3-03). 되돌릴 편집이 없으면 그대로다. 횟수 제한은 없다.
  RouteDraft undo() {
    if (!canUndo) return this;
    final history = _history.sublist(0, _history.length - 1);
    final before = _history.last;
    if (before != null) return RouteDraft._(before.points, before.distanceMeters, history, before.filledCount);
    final remaining = List<GeoPoint>.unmodifiable(points.sublist(0, points.length - 1));
    return RouteDraft._(remaining, GeoPoint.pathLength(remaining), history, filledCount);
  }

  RouteDraft get _withoutHistory => RouteDraft._(points, distanceMeters, const [], filledCount);
}
