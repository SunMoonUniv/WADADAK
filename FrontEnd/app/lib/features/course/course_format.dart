/// 코스 거리 표시. 소수 첫째 자리까지 버림한다(예: 3449m → `3.4km`).
///
/// 버림이라 등록 최소 거리(1km)에 못 미치면 `1.0km`로 보이지 않는다.
String formatKm(int meters) => '${(meters ~/ 100 / 10).toStringAsFixed(1)}km';

/// 코스 수 표시. 1240 → `1,240`(Figma A4).
String formatCount(int count) => count.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// 현재 위치에서 코스 출발점까지 거리(Figma A2 카드 `0.8 km 거리`). 100m 안은 `0.1km 거리`로 보인다.
/// 카드 평점 `★ 4.6 (128)`(Figma A2 · A6). 리뷰가 없으면 null이라 보이지 않는다.
String? formatCardRating(double? rating, int reviewCount) =>
    rating == null ? null : '★ ${rating.toStringAsFixed(1)} (${formatCount(reviewCount)})';

/// 지도 이름표 `한강 야경 5K · ★4.6`(Figma A5). 리뷰가 없으면 이름만이다.
String formatMapLabel(String name, double? rating) => rating == null ? name : '$name · ★${rating.toStringAsFixed(1)}';

String formatAway(int meters) => '${formatKm(meters < 100 ? 100 : meters)} 거리';

/// 월.일(Asia/Seoul). 예: `09.08`(Figma B9 · G3 완주 날짜).
String formatMonthDay(DateTime time) {
  final seoul = time.toUtc().add(const Duration(hours: 9));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(seoul.month)}.${two(seoul.day)}';
}

/// 오늘 사용자 지정 코스를 이미 등록했을 때 B3 · B4에 보이는 안내.
const customQuotaUsedUpMessage = '오늘은 그려서 만든 코스를 이미 등록했어요. 내일 다시 만들 수 있어요.';

/// 공개 만료까지 남은 날(Asia/Seoul 날짜 기준). 만료일 당일이 0이다.
///
/// [expiresAt]은 만료일 23:59:59(Asia/Seoul)다. 한국은 서머타임이 없어 UTC+9로 날짜를 센다.
int daysUntilExpiry(DateTime expiresAt, DateTime now) {
  DateTime seoulDate(DateTime time) {
    final seoul = time.toUtc().add(const Duration(hours: 9));
    return DateTime.utc(seoul.year, seoul.month, seoul.day);
  }

  return seoulDate(expiresAt).difference(seoulDate(now)).inDays;
}

/// 카드의 만료 표시(Figma A2 · A6 `만료 D-1`). 만료일 당일은 `만료 D-day`.
String formatExpiry(int daysLeft) => daysLeft <= 0 ? '만료 D-day' : '만료 D-$daysLeft';
