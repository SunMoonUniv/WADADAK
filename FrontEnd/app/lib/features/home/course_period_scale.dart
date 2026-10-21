import 'dart:math' as math;

import '../../core/api/course_api_client.dart';

/// 기간 슬라이더의 핸들이 멈추는 자리(FIL-09). [date]가 null이면 `전체`(처음부터)다. [position]은 슬라이더 위치(0~1).
typedef PeriodStop = ({DateTime? date, double position});

/// A3 기간 슬라이더 눈금(FIL-09). Figma A3처럼 `전체 · 1년 · 1개월 · 오늘` 글자가 같은 간격이라 구간마다 한 칸의 길이가 다르다.
///
/// - 전체 ~ 1년: 1년씩. 코스 통계를 쌓기 시작한 [dataStart] 뒤의 `N년 전`만 둔다. 그 전에는 데이터가 없다.
/// - 1년 ~ 1개월: 한 달씩.
/// - 1개월 ~ 오늘: 하루씩.
///
/// 날짜는 Asia/Seoul 날짜이고 `DateTime.utc(연, 월, 일)`로 둔다. 한 달 전 날이 없으면 그달 마지막 날이다(3/31 → 2/28).
class CoursePeriodScale {
  CoursePeriodScale(this.today) : stops = _stops(today);

  /// [now]의 Asia/Seoul 날짜를 오늘로 둔다.
  factory CoursePeriodScale.at(DateTime now) => CoursePeriodScale(seoulDate(now));

  /// 코스 통계(F11)를 쌓기 시작한 날([CoursePeriod.dataStart]). 그 전 날짜는 데이터가 없어 시작일 · 종료일 모두 이날보다 앞으로
  /// 보이지 않는다(`전체`도 이날부터).
  static final dataStart = CoursePeriod.dataStart;

  /// 눈금 글자(Figma A3 기간 라벨). 누르면 그 눈금부터 오늘까지를 고른다(A3-07).
  static const labels = ['전체', '1년', '1개월', '오늘'];

  final DateTime today;

  /// 왼쪽부터. 첫 자리는 `전체`, 마지막 자리는 오늘이다.
  final List<PeriodStop> stops;

  int get last => stops.length - 1;

  /// `1년` 눈금의 자리.
  int get oneYear => stops.indexWhere((stop) => stop.position >= 1 / 3 - 1e-9);

  /// `1개월` 눈금의 자리.
  int get oneMonth => oneYear + 11;

  /// 처음 값이자 `초기화` 값(전체 ~ 오늘).
  (int, int) get whole => (0, last);

  /// [labels]의 [label]번째 글자를 눌렀을 때 고르는 범위. 그 눈금부터 오늘까지다.
  (int, int) preset(int label) => ([0, oneYear, oneMonth, last][label], last);

  /// 슬라이더 위치에서 가장 가까운 자리. [min]보다 앞 자리는 고르지 않는다.
  int snap(double position, {int min = 0}) {
    var best = min;
    for (var i = min + 1; i < stops.length; i++) {
      if ((stops[i].position - position).abs() < (stops[best].position - position).abs()) best = i;
    }
    return best;
  }

  /// [date]에 가장 가까운 자리. null이면 `전체`다. 전에 고른 기간을 하루 지나 다시 열어도 비슷한 자리에 둔다.
  int indexOf(DateTime? date) {
    if (date == null) return 0;
    var best = 1;
    for (var i = 2; i < stops.length; i++) {
      if (stops[i].date!.difference(date).abs() < stops[best].date!.difference(date).abs()) best = i;
    }
    return best;
  }

  /// [start] ~ [end] 자리의 정렬 기간. 전체 ~ 오늘이면 기간이 없는 것과 같아 null이다.
  CoursePeriod? period(int start, int end) =>
      start == 0 && end == last ? null : CoursePeriod(start: stops[start].date, end: stops[end].date!);

  /// Figma A3 `2025. 09. 18  ~  2026. 08. 18`. [dataStart]보다 앞 날짜(`전체` 포함)는 [dataStart]로 보인다.
  /// 서버에도 그 날짜로 간다([CoursePeriod]). 그래서 통계를 쌓은 지 한 달이 안 된 동안 `1년 ~ 1개월`은 `오늘`과 같다.
  String format(int start, int end) {
    DateTime shown(DateTime? date) => date == null || date.isBefore(dataStart) ? dataStart : date;
    return '${_dotted(shown(stops[start].date))}  ~  ${_dotted(shown(stops[end].date))}';
  }

  /// [time]의 Asia/Seoul 날짜. 한국은 서머타임이 없어 UTC+9로 센다.
  static DateTime seoulDate(DateTime time) {
    final seoul = time.toUtc().add(const Duration(hours: 9));
    return DateTime.utc(seoul.year, seoul.month, seoul.day);
  }

  /// [date]에서 [months]달 전. 그달에 같은 날이 없으면 마지막 날이다.
  static DateTime monthsAgo(DateTime date, int months) {
    final total = date.year * 12 + date.month - 1 - months;
    final year = total ~/ 12, month = total % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return DateTime.utc(year, month, math.min(date.day, lastDay));
  }

  static List<PeriodStop> _stops(DateTime today) {
    const third = 1 / 3;
    // 데이터가 있는 해의 `N년 전`(N ≥ 2). 왼쪽이 오래된 쪽이다.
    final years = [for (var n = 2; !monthsAgo(today, 12 * n).isBefore(dataStart); n++) n].reversed.toList();
    final monthAgo = monthsAgo(today, 1);
    final days = today.difference(monthAgo).inDays;
    return [
      (date: null, position: 0.0),
      for (final (i, n) in years.indexed) (date: monthsAgo(today, 12 * n), position: (i + 1) / (years.length + 1) * third),
      for (var m = 12; m >= 1; m--) (date: monthsAgo(today, m), position: third + (12 - m) / 11 * third),
      for (var d = 1; d <= days; d++) (date: monthAgo.add(Duration(days: d)), position: 2 * third + d / days * third),
    ];
  }

  static String _dotted(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}. ${two(date.month)}. ${two(date.day)}';
  }
}
