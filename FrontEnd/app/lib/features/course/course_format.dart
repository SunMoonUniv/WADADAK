/// 코스 거리 표시. 소수 첫째 자리까지 버림한다(예: 3449m → `3.4km`).
///
/// 버림이라 등록 최소 거리(1km)에 못 미치면 `1.0km`로 보이지 않는다.
String formatKm(int meters) => '${(meters ~/ 100 / 10).toStringAsFixed(1)}km';

/// 오늘 사용자 지정 코스를 이미 등록했을 때 B3 · B4에 보이는 안내.
const customQuotaUsedUpMessage = '오늘은 그려서 만든 코스를 이미 등록했어요. 내일 다시 만들 수 있어요.';
