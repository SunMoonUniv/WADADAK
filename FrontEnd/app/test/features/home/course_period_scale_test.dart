import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/features/home/course_period_scale.dart';

void main() {
  DateTime day(int year, int month, int date) => DateTime.utc(year, month, date);

  test('steps by month from 1년 to 1개월 and by day from 1개월 to 오늘, with 전체 right before 1년 in the first year', () {
    final scale = CoursePeriodScale(day(2026, 10, 19));

    // 전체 · 1년 + 한 달씩 11칸 · 1개월(9/19) + 하루씩 30칸 · 오늘
    expect(scale.stops.length, 1 + 12 + 30);
    expect(scale.stops.first, (date: null, position: 0.0));
    expect((scale.oneYear, scale.oneMonth, scale.last), (1, 12, 42));
    expect(scale.stops[scale.oneYear].date, day(2025, 10, 19));
    expect(scale.stops[scale.oneYear].position, closeTo(1 / 3, 1e-9));
    expect(scale.stops[2].date, day(2025, 11, 19));
    expect(scale.stops[scale.oneMonth].date, day(2026, 9, 19));
    expect(scale.stops[scale.oneMonth].position, closeTo(2 / 3, 1e-9));
    expect(scale.stops[scale.oneMonth + 1].date, day(2026, 9, 20));
    expect(scale.stops[scale.last].date, day(2026, 10, 19));
    expect(scale.stops[scale.last].position, closeTo(1, 1e-9));
  });

  test('adds a stop for each earlier year that has data', () {
    final scale = CoursePeriodScale(day(2028, 10, 25));

    // 2년 전(2026-10-25)은 통계를 쌓기 시작한 뒤라 있고, 3년 전은 없다
    expect(scale.stops[1].date, day(2026, 10, 25));
    expect(scale.stops[1].position, closeTo(1 / 6, 1e-9));
    expect(scale.oneYear, 2);
    expect(scale.stops[scale.oneYear].date, day(2027, 10, 25));
    expect(scale.format(0, scale.last), '2026. 10. 19  ~  2028. 10. 25', reason: '전체는 통계를 쌓기 시작한 날부터');
  });

  test('shows the start from the day the stats began until a year of data', () {
    final scale = CoursePeriodScale(day(2027, 3, 1));

    expect(scale.format(scale.oneYear, scale.last), '2026. 10. 19  ~  2027. 03. 01', reason: '1년 전(2026-03-01)은 통계를 쌓기 전');
    expect(scale.format(0, scale.last), '2026. 10. 19  ~  2027. 03. 01');
    expect(scale.format(scale.oneMonth, scale.last), '2027. 02. 01  ~  2027. 03. 01');
    expect(scale.format(scale.oneYear + 8, scale.last), '2026. 11. 01  ~  2027. 03. 01', reason: '통계 시작 뒤 날짜는 그대로');
  });

  test('uses the last day of a shorter month', () {
    final scale = CoursePeriodScale(day(2027, 3, 31));

    expect(scale.stops[scale.oneMonth].date, day(2027, 2, 28));
    expect(scale.last, scale.oneMonth + 31);
    expect(CoursePeriodScale.monthsAgo(day(2028, 2, 29), 12), day(2027, 2, 28));
    expect(CoursePeriodScale.monthsAgo(day(2026, 1, 15), 1), day(2025, 12, 15));
  });

  test('picks the period by the labels, by dragging, and turns it into the request', () {
    final scale = CoursePeriodScale(day(2026, 10, 19));

    expect(scale.whole, (0, 42));
    expect([for (var i = 0; i < 4; i++) scale.preset(i)], [(0, 42), (1, 42), (12, 42), (42, 42)]);

    expect(scale.snap(0), 0);
    expect(scale.snap(1 / 3), scale.oneYear);
    // 1년 ~ 1개월 구간의 6번째 칸(6개월 전)
    expect(scale.stops[scale.snap(0.52)].date, day(2026, 4, 19));
    expect(scale.snap(0.999), scale.last);
    expect(scale.snap(0, min: 1), 1, reason: '종료 핸들은 전체에 오지 않는다');

    expect(scale.indexOf(null), 0);
    expect(scale.indexOf(day(2026, 10, 19)), scale.last);
    expect(scale.stops[scale.indexOf(day(2026, 4, 20))].date, day(2026, 4, 19));
    expect(scale.indexOf(day(2020, 1, 1)), 1);

    expect(scale.period(0, 42), isNull, reason: '전체 ~ 오늘은 기간이 없는 것과 같다');
    expect(scale.period(12, 42), CoursePeriod(start: day(2026, 9, 19), end: day(2026, 10, 19)));
    expect(scale.period(0, 12), CoursePeriod(end: day(2026, 9, 19)));
    expect(scale.period(42, 42), CoursePeriod(start: day(2026, 10, 19), end: day(2026, 10, 19)), reason: '오늘 하루');

    expect(scale.format(0, 42), '2026. 10. 19  ~  2026. 10. 19');
    expect(scale.format(1, 42), '2026. 10. 19  ~  2026. 10. 19', reason: '1년 전은 통계를 쌓기 전이라 전체처럼 통계 시작일부터');
    expect(scale.format(1, 12), '2026. 10. 19  ~  2026. 10. 19', reason: '1개월 전도 통계를 쌓기 전이라 통계 시작일');
    expect(scale.period(1, 42), CoursePeriod(start: day(2025, 10, 19), end: day(2026, 10, 19)),
        reason: '눈금 날짜 그대로 들고 있다가 보낼 때 통계 시작일로 바꾼다(다시 열면 같은 자리)');
  });

  test('takes today in Asia/Seoul', () {
    expect(CoursePeriodScale.at(DateTime.utc(2026, 10, 19, 15, 30)).today, day(2026, 10, 20));
    expect(CoursePeriodScale.at(DateTime.utc(2026, 10, 19, 14, 59)).today, day(2026, 10, 19));
  });
}
