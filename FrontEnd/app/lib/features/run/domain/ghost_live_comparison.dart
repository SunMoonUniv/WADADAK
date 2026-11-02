import '../../../core/map/geo_point.dart';

/// Signed values from the existing live replay comparison, never from UI text.
class GhostLiveComparison {
  const GhostLiveComparison({
    this.position,
    this.distanceM,
    this.timeDeltaMs,
    this.ghostProgress,
  });

  final GeoPoint? position;

  /// Positive means the runner is ahead.
  final double? distanceM;

  /// Runner arrival minus ghost arrival at the same course position.
  final double? timeDeltaMs;
  final double? ghostProgress;

  String get distance => distanceM == null
      ? '—'
      : '${distanceM!.abs().round()}m ${distanceM! >= 0 ? '앞서요' : '뒤에 있어요'}';
  String get time => timeDeltaMs == null
      ? '—'
      : '${(timeDeltaMs!.abs() / 1000).round()}초 ${timeDeltaMs! <= 0 ? '앞서요' : '뒤에 있어요'}';

  String get value => distanceM == null
      ? '—'
      : '${distanceM!.round() > 0 ? '+' : ''}${distanceM!.round()} m';
  String get title => distanceM == null
      ? '고스트 위치를 확인하고 있어요'
      : distanceM!.round() == 0
      ? '고스트와 나란히 달리고 있어요'
      : distanceM! > 0
      ? '고스트보다 앞서고 있어요'
      : '고스트를 따라잡고 있어요';
  String get caption => timeDeltaMs == null
      ? '시간차 확인 중'
      : timeDeltaMs!.abs() < 500
      ? '같은 시간에 통과했어요'
      : '약 ${(timeDeltaMs!.abs() / 1000).round()}초 ${timeDeltaMs! < 0 ? '앞서는 중' : '뒤처지는 중'}';
  String get message => distanceM == null
      ? 'GPS가 확인되면 격차를 표시해요.'
      : distanceM! >= 0
      ? '지금 페이스를 이어가세요.'
      : '나만의 페이스로 차근차근 따라가세요.';
}
