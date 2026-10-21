import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../core/api/api_client.dart';
import '../../core/api/course_api_client.dart';
import '../../core/error_message.dart';
import '../course/course_format.dart';
import 'course_list_sheet.dart';
import 'course_period_scale.dart';

/// A3에 넘기는 값. 지금 걸린 필터 · 정렬 · 인기순 기간과, 예상 코스 수를 셀 지도 범위(홈에 보이는 범위)다.
typedef CourseFilterRequest = ({CourseFilter filter, CourseListSort sort, CoursePeriod? period, MapArea area});

/// A3에서 `코스 N개 보기`로 확정한 필터 · 정렬 · 기간. 기간은 인기순일 때만 있고, 전체 ~ 오늘이면 null이다.
typedef CourseFilterChoice = ({CourseFilter filter, CourseListSort sort, CoursePeriod? period});

/// A3 코스 필터. 정렬(인기순이면 기간 슬라이더도) · 거리 · 난이도 · 최소 평점 · 코스 태그 · 코스 유형을 고른다.
/// 필터를 바꿀 때마다 약 300ms 뒤 지금 지도 범위의 예상 코스 수를 다시 센다(FIL-07).
/// 정렬 · 기간은 순서만 바꿔 수가 같아 다시 세지 않는다.
/// 고르는 동안은 홈에 적용하지 않고 `코스 N개 보기`를 누르면 확정해 돌려준다. 뒤로 가면 버린다.
class CourseFilterScreen extends ConsumerStatefulWidget {
  const CourseFilterScreen({super.key, required this.request, this.now = DateTime.now});

  final CourseFilterRequest request;

  /// 기간 슬라이더의 오늘(Asia/Seoul)을 정하는 시각.
  final DateTime Function() now;

  static const countFailedMessage = '코스 수를 확인하지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.';

  /// 예상 코스 수를 세는 동안 버튼 글자(A3 Loading).
  static const countingLabel = '코스 수 확인 중…';

  @override
  ConsumerState<CourseFilterScreen> createState() => _CourseFilterScreenState();
}

class _CourseFilterScreenState extends ConsumerState<CourseFilterScreen> {
  /// 조건을 바꾸고 예상 코스 수를 다시 세기까지(FIL-07).
  static const _countDelay = Duration(milliseconds: 300);

  late CourseListSort _sort;

  /// 기간 슬라이더 눈금(FIL-09). 화면을 연 날이 오늘이다.
  late final CoursePeriodScale _periods;

  /// 기간. [CoursePeriodScale.stops]의 자리이고 시작 ≤ 종료다. 종료는 `전체` 자리(0)에 오지 않는다.
  /// 다른 정렬을 골라도 자리는 남지만 돌려줄 때는 인기순일 때만 넣는다.
  late int _periodStart, _periodEnd;

  /// 거리 범위(km). [_DistanceScale.stops] 중 하나다.
  late double _minKm, _maxKm;
  late Set<Difficulty> _difficulties;
  double? _minRating;
  late Set<CourseTag> _tags;
  CourseType? _courseType;

  /// 예상 코스 수. 아직 모르거나 세지 못했으면 null.
  int? _count;

  /// 조건을 바꾼 뒤 새 예상 코스 수를 받기 전이다. 직전 수는 지금 조건의 수가 아니라 보이지 않는다.
  var _counting = true;
  Timer? _countTimer;

  /// 가장 최근 세기 번호. 늦게 도착한 예전 응답은 버린다.
  var _countRequest = 0;

  @override
  void initState() {
    super.initState();
    final filter = widget.request.filter;
    _sort = widget.request.sort;
    _periods = CoursePeriodScale.at(widget.now());
    final period = widget.request.period;
    if (period == null) {
      _setPeriod(_periods.whole);
    } else {
      final start = _periods.indexOf(period.start);
      _setPeriod((start, math.max(_periods.indexOf(period.end), math.max(start, 1))));
    }
    _minKm = (filter.minDistanceMeters ?? 1000) / 1000;
    _maxKm = (filter.maxDistanceMeters ?? 20000) / 1000;
    _difficulties = {...filter.difficulties};
    _minRating = filter.minRating;
    _tags = {...filter.tags};
    _courseType = filter.courseType;
    _countNow();
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    super.dispose();
  }

  CourseFilter get _filter => CourseFilter(
        // 양 끝은 조건이 없는 것과 같다. 1km는 등록 최소 거리, 20km는 `20km+`다.
        minDistanceMeters: _minKm <= _DistanceScale.min ? null : (_minKm * 1000).round(),
        maxDistanceMeters: _maxKm >= _DistanceScale.max ? null : (_maxKm * 1000).round(),
        difficulties: {..._difficulties},
        minRating: _minRating,
        tags: {..._tags},
        courseType: _courseType,
      );

  /// 인기순 기간. 인기순이 아니거나 전체 ~ 오늘이면 null.
  CoursePeriod? get _period => _sort == CourseListSort.popular ? _periods.period(_periodStart, _periodEnd) : null;

  /// 조건을 바꾸고 예상 코스 수를 다시 센다. 정렬 · 기간은 수가 같아 [setState]만 한다.
  void _edit(VoidCallback change) {
    setState(() {
      change();
      _counting = true;
    });
    _countTimer?.cancel();
    _countTimer = Timer(_countDelay, _countNow);
  }

  Future<void> _countNow() async {
    final request = ++_countRequest;
    final area = widget.request.area;
    if (!_counting) setState(() => _counting = true);
    try {
      final map = await ref
          .read(courseApiClientProvider)
          .mapCourses(southWest: area.southWest, northEast: area.northEast, filter: _filter);
      if (!mounted || request != _countRequest) return;
      setState(() {
        _count = map.totalCount;
        _counting = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _countRequest) return;
      setState(() {
        _count = null;
        _counting = false;
      });
      showError(context, e, message: CourseFilterScreen.countFailedMessage, onRetry: _countNow);
    }
  }

  /// 모든 조건을 처음 값으로 되돌린다(A3-05). 홈에는 `코스 N개 보기`를 눌러야 적용된다.
  void _reset() => _edit(() {
        _sort = CourseListSort.initial;
        _setPeriod(_periods.whole);
        _minKm = _DistanceScale.min;
        _maxKm = _DistanceScale.max;
        _difficulties = {};
        _minRating = null;
        _tags = {};
        _courseType = null;
      });

  /// 인기순이 아니면 기간은 넣지 않는다(정렬을 바꾸면 전체로).
  void _apply() => context.pop<CourseFilterChoice>((filter: _filter, sort: _sort, period: _period));

  void _setPeriod((int, int) range) {
    _periodStart = range.$1;
    _periodEnd = range.$2;
  }

  void _pickPeriod((int, int) range) => setState(() => _setPeriod(range));

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(
        title: '필터',
        onBack: () => context.pop(),
        action: WdAppBarAction.button('초기화', onTap: _reset),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s32),
        children: [
          _section('정렬', [
            _chips([
              for (final sort in CourseListSort.values)
                _chip(sort.label, selected: _sort == sort, onTap: () => setState(() => _sort = sort)),
            ]),
            // 기간 슬라이더(FIL-09)는 인기순일 때만. Figma A3: 눈금 글자 · 슬라이더 · 고른 날짜.
            if (_sort == CourseListSort.popular) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final (i, label) in CoursePeriodScale.labels.indexed)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _pickPeriod(_periods.preset(i)),
                      child: Text(label, style: _scaleLabelStyle),
                    ),
                ],
              ),
              _RangeTrack(
                start: _periods.stops[_periodStart].position,
                end: _periods.stops[_periodEnd].position,
                onChanged: (start, end) {
                  final from = _periods.snap(start);
                  final to = _periods.snap(end, min: math.max(from, 1));
                  if (from != _periodStart || to != _periodEnd) _pickPeriod((from, to));
                },
              ),
              Text(
                _periods.format(_periodStart, _periodEnd),
                textAlign: TextAlign.center,
                style: WdText.raw(12, FontWeight.w700, 18).copyWith(color: WdColors.ink),
              ),
            ],
          ]),
          _section('거리', [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final label in const ['1km', '5km', '10km', '20km+']) Text(label, style: _scaleLabelStyle),
              ],
            ),
            _RangeTrack(
              start: _DistanceScale.at(_minKm),
              end: _DistanceScale.at(_maxKm),
              onChanged: (start, end) {
                final min = _DistanceScale.snap(start), max = _DistanceScale.snap(end);
                if (min != _minKm || max != _maxKm) {
                  _edit(() {
                    _minKm = min;
                    _maxKm = max;
                  });
                }
              },
            ),
            Text(
              '${_km(_minKm)}  ~  ${_km(_maxKm)}',
              textAlign: TextAlign.center,
              style: WdText.ko16Bold.copyWith(color: WdColors.ink),
            ),
            Text(
              _paceHint(_minKm, _maxKm),
              textAlign: TextAlign.center,
              style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted),
            ),
          ]),
          _section('난이도', [
            _chips([
              // 아무것도 고르지 않으면 `전체`다(FIL-03).
              _chip('전체', selected: _difficulties.isEmpty, onTap: () => _edit(() => _difficulties = {})),
              for (final difficulty in Difficulty.values)
                _chip(
                  difficulty.label,
                  selected: _difficulties.contains(difficulty),
                  onTap: () => _edit(() => _difficulties = _toggled(_difficulties, difficulty)),
                ),
            ]),
          ]),
          _section('최소 평점', [
            _chips([
              _chip('전체', selected: _minRating == null, onTap: () => _edit(() => _minRating = null)),
              for (final rating in CourseFilter.minRatings)
                _chip(
                  '★${rating.toStringAsFixed(1)}+',
                  selected: _minRating == rating,
                  onTap: () => _edit(() => _minRating = rating),
                ),
            ]),
          ]),
          _section('코스 태그', [
            // Figma A3처럼 네 개씩 두 줄(FIL-04 순서).
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WdSpace.s6,
              children: [
                for (final row in [CourseTag.values.take(4), CourseTag.values.skip(4)])
                  _chips([
                    for (final tag in row)
                      _chip(tag.label, selected: _tags.contains(tag), onTap: () => _edit(() => _tags = _toggled(_tags, tag))),
                  ]),
              ],
            ),
          ]),
          _section('코스 유형', [
            _chips([
              _chip('전체', selected: _courseType == null, onTap: () => _edit(() => _courseType = null)),
              for (final type in CourseType.values)
                _chip(type.label, selected: _courseType == type, onTap: () => _edit(() => _courseType = type)),
            ]),
          ]),
        ],
      ),
      bottomNavigationBar: WdBottomBar.pinned(
        primary: WdButton(
          _counting
              ? CourseFilterScreen.countingLabel
              : count == null
                  ? '코스 보기'
                  : '코스 ${formatCount(count)}개 보기',
          // 세는 중에도 누르면 지금 조건을 적용한다. 적용에는 수가 필요 없다.
          onPressed: _apply,
        ),
      ),
    );
  }

  /// 슬라이더 위 눈금 글자(Figma A3 기간 라벨 · 거리).
  static final _scaleLabelStyle = WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted);

  static Set<T> _toggled<T>(Set<T> values, T value) =>
      values.contains(value) ? ({...values}..remove(value)) : {...values, value};

  /// 섹션 제목 + 내용. 섹션 안팎 간격은 Figma A3 Body처럼 16이다.
  static Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: WdSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WdSpace.s16,
          children: [
            Text(title, style: WdText.ko16Bold.copyWith(color: WdColors.muted)),
            ...children,
          ],
        ),
      );

  static Widget _chips(List<Widget> chips) => Wrap(spacing: WdSpace.s6, runSpacing: WdSpace.s6, children: chips);

  /// Figma A3 칩은 높이 36이다.
  static Widget _chip(String label, {required bool selected, required VoidCallback onTap}) =>
      WdFilterChip(label, selected: selected, height: 36, onTap: onTap);

  /// 3 → `3 km`, 3.5 → `3.5 km`, 20 → `20 km+`. 소수점 첫째 자리까지 보인다(FIL-02).
  static String _km(double km) {
    if (km >= _DistanceScale.max) return '20 km+';
    return '${km == km.roundToDouble() ? km.round() : km.toStringAsFixed(1)} km';
  }

  /// Figma A3 `5′30″/km 기준 약 17 ~ 44분 코스`.
  static String _paceHint(double minKm, double maxKm) {
    int minutes(double km) => (km * 5.5).round();
    final open = maxKm >= _DistanceScale.max ? '+' : '';
    return '5′30″/km 기준 약 ${minutes(minKm)} ~ ${minutes(maxKm)}분$open 코스';
  }
}

/// 거리 슬라이더 눈금(FIL-02). Figma A3처럼 1 · 5 · 10 · 20km+ 글자가 같은 간격이라 구간마다 길이가 다르다.
/// 핸들은 10km까지 0.5km, 그 뒤로 1km마다 멈춘다. 끝(20km)은 `20km+`(상한 없음)다.
abstract final class _DistanceScale {
  static const min = 1.0;
  static const max = 20.0;
  static const _marks = [1.0, 5.0, 10.0, 20.0];

  static final stops = [for (var half = 2; half < 20; half++) half / 2, for (var km = 10; km <= 20; km++) km.toDouble()];

  /// [km]의 슬라이더 위치(0~1).
  static double at(double km) {
    for (var i = 1; i < _marks.length; i++) {
      if (km <= _marks[i]) {
        final within = (km - _marks[i - 1]) / (_marks[i] - _marks[i - 1]);
        return (i - 1 + within) / (_marks.length - 1);
      }
    }
    return 1;
  }

  /// 슬라이더 위치에서 가장 가까운 눈금(km).
  static double snap(double position) =>
      stops.reduce((a, b) => (at(a) - position).abs() <= (at(b) - position).abs() ? a : b);
}

/// 범위 슬라이더(기간 · 거리). Figma A3: 트랙 6(soft) · 고른 구간 dark · 핸들 16(흰 바탕 · dark 테두리 2).
/// 위치는 0~1이고, 눈금에 맞추는 일은 [onChanged]를 받는 쪽이 한다.
class _RangeTrack extends StatelessWidget {
  const _RangeTrack({required this.start, required this.end, required this.onChanged});

  final double start, end;
  final void Function(double start, double end) onChanged;

  @override
  Widget build(BuildContext context) => SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 6,
          activeTrackColor: WdColors.dark,
          inactiveTrackColor: WdColors.soft,
          rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
          rangeThumbShape: const _Thumb(),
          overlayShape: SliderComponentShape.noOverlay,
          showValueIndicator: ShowValueIndicator.never,
        ),
        child: RangeSlider(
          values: RangeValues(start, end),
          // 핸들이 트랙 양 끝에 오도록 옆 여백을 두지 않는다. 위아래는 누르기 쉽게 넓힌다.
          padding: const EdgeInsets.symmetric(vertical: WdSpace.s8),
          onChanged: (values) => onChanged(values.start, values.end),
        ),
      );
}

class _Thumb extends RangeSliderThumbShape {
  const _Thumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size.square(16);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool isOnTop = false,
    TextDirection textDirection = TextDirection.ltr,
    required SliderThemeData sliderTheme,
    Thumb thumb = Thumb.start,
    bool isPressed = false,
  }) {
    context.canvas
      ..drawCircle(center, 7, Paint()..color = WdColors.white)
      ..drawCircle(
        center,
        7,
        Paint()
          ..color = WdColors.dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }
}
