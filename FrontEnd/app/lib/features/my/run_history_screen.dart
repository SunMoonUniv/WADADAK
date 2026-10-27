import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../routes.dart';
import '../review/review_entry.dart';
import '../run/application/run_controller.dart';
import '../run/domain/run_models.dart';
import 'run_history_rows.dart';

/// I1 · 내 러닝 기록. MY에서 연다(하단 탭이 보인다, Figma I1).
///
/// 위에서부터 유형 탭 · 달 이동과 그 달 요약 · 이번 주 주행 거리 · 최근 기록이다(2026-10-22 사용자 결정).
/// - 유형 탭은 아래 전부(요약 · 차트 · 목록)에 적용한다. 고스트 대결 탭은 고스트(F9)가 생길 때까지 비어 있다.
/// - `‹ ›`로 달을 바꾸면 요약 3칸만 바뀐다. 주간 차트는 늘 이번 주, 목록은 늘 전체 최근 순이다.
/// - Figma의 `필터` 버튼은 거를 조건이 정해지지 않아 두지 않는다.
///
/// 기록은 무한 스크롤로 받는다(2026-10-27 사용자 결정. 매일 뛰면 한 달에 30개씩 쌓인다).
/// 처음엔 한 페이지(20개)를 받고, 요약에 필요한 만큼(고른 달 · 이번 주)만 더 받는다. 목록은 끝에 가까워지면 이어 받는다.
/// 전체 개수는 끝까지 받아야 알 수 있어서 탭에 개수를 붙이지 않는다.
///
/// 코스 러닝 카드의 [코스 상세]는 B1, [리뷰 쓰기]는 리뷰 진입(`openReviewWriter`)으로 간다.
/// 기록 데이터(기기 · 서버 · 동기화 · 삭제)는 달리기 담당의 `runController`를 그대로 쓴다.
class MyRunHistoryScreen extends ConsumerStatefulWidget {
  const MyRunHistoryScreen({super.key, this.now = DateTime.now});

  /// 오늘. 테스트에서 날짜를 고정한다.
  final DateTime Function() now;

  @override
  ConsumerState<MyRunHistoryScreen> createState() => _MyRunHistoryScreenState();
}

class _MyRunHistoryScreenState extends ConsumerState<MyRunHistoryScreen> {
  late final RunController _runs;
  var _type = RunType.all;

  /// 요약을 보는 달(1일). 처음은 이번 달이다.
  late DateTime _month = DateTime(widget.now().year, widget.now().month);

  @override
  void initState() {
    super.initState();
    _runs = ref.read(runControllerProvider)..addListener(_loadForSummary);
    Future.microtask(() async {
      await _runs.bindOwner();
      if (!mounted) return;
      await _runs.loadHistory();
      _loadForSummary();
    });
  }

  @override
  void dispose() {
    _runs.removeListener(_loadForSummary);
    super.dispose();
  }

  /// 요약에 필요한 날(고른 달 1일과 이번 주 월요일 중 이른 날)
  DateTime get _summaryFrom {
    final today = widget.now();
    final monday = DateTime(today.year, today.month, today.day).subtract(Duration(days: today.weekday - 1));
    return _month.isBefore(monday) ? _month : monday;
  }

  /// 받은 기록이 요약에 필요한 날까지 닿지 않았으면 한 페이지 더 받는다. 기록은 최근 순으로 오므로
  /// 가장 오래된 기록이 그날보다 앞서면 멈춘다. 실패하면 멈추고 배너로 다시 받게 한다.
  void _loadForSummary() {
    if (!mounted || _runs.loadingHistory || _runs.nextCursor == null || _runs.historyNotice != null) return;
    final rows = runHistoryRows(local: _runs.records, remote: _runs.remoteRecords, deletedIds: _runs.deletedIds);
    if (rows.isEmpty || !rows.last.startedAt.toLocal().isBefore(_summaryFrom)) {
      unawaited(_runs.loadHistory(more: true));
    }
  }

  /// 목록 끝에 가까워지거나 [이전 기록 더 보기]를 누르면 다음 페이지를 받는다.
  void _loadMore() {
    if (_runs.loadingHistory || _runs.nextCursor == null || _runs.historyNotice != null) return;
    unawaited(_runs.loadHistory(more: true));
  }

  void _moveMonth(int by) {
    setState(() => _month = DateTime(_month.year, _month.month + by));
    _loadForSummary();
  }

  Future<void> _refresh() async {
    await _runs.sync(manual: true);
    await _runs.loadHistory();
    _loadForSummary();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _runs,
    builder: (context, _) {
      final all = runHistoryRows(local: _runs.records, remote: _runs.remoteRecords, deletedIds: _runs.deletedIds);
      final rows = all.where(_type.includes).toList();
      final today = widget.now();
      final thisMonth = DateTime(today.year, today.month);
      // 다 받았으면 가장 오래된 기록이 있는 달까지만 뒤로 갈 수 있다. 덜 받았으면 더 받아 가며 간다
      final firstMonth = _runs.nextCursor != null || all.isEmpty
          ? (all.isEmpty ? thisMonth : DateTime(1970))
          : DateTime(all.last.startedAt.toLocal().year, all.last.startedAt.toLocal().month);
      final summary = monthSummary(rows, _month);
      // 고스트 대결 기록은 아직 없어서 더 받아도 나오지 않는다
      final canLoadMore = _runs.nextCursor != null && _type != RunType.ghost;
      final header = _Header(
        month: _month,
        isThisMonth: _month == thisMonth,
        summary: summary,
        week: weekDistances(rows, today),
        todayIndex: today.weekday - 1,
        onPrevious: _month.isAfter(firstMonth) ? () => _moveMonth(-1) : null,
        onNext: _month.isBefore(thisMonth) ? () => _moveMonth(1) : null,
        notice: _runs.historyNotice == null
            ? null
            : TextButton(
                onPressed: _runs.loadingHistory ? null : () => _runs.loadHistory(more: _runs.nextCursor != null),
                child: const Text('다시 불러오기'),
              ),
        empty: rows.isEmpty && !_runs.loadingHistory && !canLoadMore ? _emptyText : null,
      );
      final footer = _runs.loadingHistory
          ? const Padding(
              padding: EdgeInsets.all(WdSpace.s16),
              child: Center(child: CircularProgressIndicator(color: WdColors.ink)),
            )
          : canLoadMore && _runs.historyNotice == null
          // 목록이 짧아 스크롤할 수 없을 때(코스 러닝 탭 등)도 이어 받을 수 있게 둔다
          ? Padding(
              padding: const EdgeInsets.only(top: WdSpace.s16),
              child: WdButton('이전 기록 더 보기', variant: WdButtonVariant.secondary, onPressed: _loadMore),
            )
          : const SizedBox.shrink();
      return DefaultTabController(
        length: RunType.values.length,
        child: Scaffold(
          backgroundColor: WdColors.paper,
          appBar: WdAppBar(title: '내 기록', onBack: () => context.pop()),
          body: Column(
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: WdColors.line))),
                child: WdTabBar(
                  tabs: [for (final t in RunType.values) t.label],
                  onTap: (index) => setState(() => _type = RunType.values[index]),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: WdColors.ink,
                  onRefresh: _refresh,
                  child: NotificationListener<ScrollNotification>(
                    // 끝에서 400px 안으로 내려오면 다음 페이지를 받는다
                    onNotification: (notification) {
                      if (notification.metrics.extentAfter < 400 &&
                          notification is ScrollUpdateNotification &&
                          notification.metrics.axisDirection == AxisDirection.down &&
                          canLoadMore) {
                        _loadMore();
                      }
                      return false;
                    },
                    // builder: 화면에 보이는 카드만 만든다. 기록이 많아도 가볍다
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
                      itemCount: rows.length + 2,
                      itemBuilder: (context, index) {
                        if (index == 0) return header;
                        if (index == rows.length + 1) return footer;
                        return Padding(
                          padding: const EdgeInsets.only(top: WdSpace.s12),
                          child: RunRecordCard(rows[index - 1]),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  String get _emptyText => switch (_type) {
    RunType.all => '아직 러닝 기록이 없어요. 첫 러닝을 시작해 보세요.',
    RunType.free => '아직 자유 러닝 기록이 없어요.',
    RunType.course => '아직 코스 러닝 기록이 없어요.',
    RunType.ghost => '아직 고스트 대결 기록이 없어요.',
  };
}

/// 목록 위쪽: 달 이동 · 요약 3칸 · 주간 주행 거리 · "최근 기록" 제목(과 불러오기 실패 · 빈 목록 안내).
class _Header extends StatelessWidget {
  const _Header({
    required this.month,
    required this.isThisMonth,
    required this.summary,
    required this.week,
    required this.todayIndex,
    required this.onPrevious,
    required this.onNext,
    required this.notice,
    required this.empty,
  });

  final DateTime month;
  final bool isThisMonth;
  final MonthSummary summary;
  final List<double> week;
  final int todayIndex;
  final VoidCallback? onPrevious, onNext;

  /// 서버 기록을 못 받았을 때 배너 아래 [다시 불러오기]
  final Widget? notice;

  /// 보일 기록이 없을 때 문구
  final String? empty;

  static final _heading = WdText.ko16Bold.copyWith(color: WdColors.ink);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _MonthHeader(month: month, onPrevious: onPrevious, onNext: onNext),
      const SizedBox(height: WdSpace.s12),
      WdStatSummary([
        (isThisMonth ? '이번 달 거리' : '${month.month}월 거리', '${(summary.distanceMeters / 1000).toStringAsFixed(1)} km'),
        ('러닝', '${summary.runs}회'),
        ('평균 페이스', formatRunPace(summary.paceSecondsPerKm)),
      ]),
      const SizedBox(height: WdSpace.s24),
      Text('주간 주행 거리', style: _heading),
      const SizedBox(height: WdSpace.s12),
      _WeekChart(meters: week, todayIndex: todayIndex),
      const SizedBox(height: WdSpace.s24),
      Text('최근 기록', style: _heading),
      if (notice != null) ...[
        const SizedBox(height: WdSpace.s12),
        const WdInfoBanner('서버 기록을 불러오지 못했어요. 기기에 저장된 기록은 볼 수 있어요.', tone: WdBannerTone.warning),
        notice!,
      ],
      if (empty != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: WdSpace.s32),
          child: Center(child: Text(empty!, style: WdText.label12.copyWith(color: WdColors.muted))),
        ),
    ],
  );
}

/// "2026년 9월" + ‹ ›. 이번 달보다 뒤나 (다 받았을 때) 첫 기록보다 앞으로는 못 간다(버튼이 흐려진다).
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.onPrevious, required this.onNext});

  final DateTime month;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text('${month.year}년 ${month.month}월', style: WdText.ko16Bold.copyWith(color: WdColors.ink))),
      _arrow('‹', '이전 달', onPrevious),
      _arrow('›', '다음 달', onNext),
    ],
  );

  static Widget _arrow(String glyph, String label, VoidCallback? onTap) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox.square(
        dimension: 32,
        child: Center(
          child: Text(
            glyph,
            style: WdText.raw(18, FontWeight.w400, 24).copyWith(color: onTap == null ? WdColors.line : WdColors.muted),
          ),
        ),
      ),
    ),
  );
}

/// 이번 주(월~일) 요일별 주행 거리 막대. 오늘 막대만 진하다(Figma I1).
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.meters, required this.todayIndex});

  final List<double> meters;
  final int todayIndex;

  static const _days = ['월', '화', '수', '목', '금', '토', '일'];
  static const _height = 64.0;

  @override
  Widget build(BuildContext context) {
    final most = meters.fold(0.0, (a, b) => a > b ? a : b);
    return Column(
      spacing: WdSpace.s6,
      children: [
        SizedBox(
          height: _height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: WdSpace.s6,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Semantics(
                    label: '${_days[i]} ${(meters[i] / 1000).toStringAsFixed(1)}km',
                    child: Container(
                      // 거리가 있으면 가장 긴 날 대비 높이, 없으면 막대 없음
                      height: most == 0 || meters[i] == 0 ? 0 : (_height * meters[i] / most).clamp(6.0, _height),
                      decoration: BoxDecoration(
                        color: i == todayIndex ? WdColors.ink : WdColors.soft,
                        borderRadius: BorderRadius.circular(WdRadius.r8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Row(
          spacing: WdSpace.s6,
          children: [
            for (final day in _days)
              Expanded(
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: WdText.label12.copyWith(color: WdColors.muted),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Figma I1 기록 카드: 썸네일 · 제목(코스 이름 또는 자유 러닝) · 거리 · 시간 · 페이스 · 결과 태그 · 날짜,
/// 코스 러닝이면 아래에 [코스 상세] · [리뷰 쓰기].
class RunRecordCard extends ConsumerWidget {
  const RunRecordCard(this.row, {super.key});

  final RunHistoryRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = row.course;
    return WdSurface(
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s14, vertical: 13),
      onTap: () => context.push(Routes.myRecord(row.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s8,
        children: [
          Row(
            spacing: WdSpace.s12,
            children: [
              const WdRouteThumbnail(width: 52, height: 52),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      // 아직 올리지 않은 기록은 코스 판정 전이라 자유 러닝인지 모른다
                      course?.courseName ?? (row.synced ? '자유 러닝' : '러닝'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WdText.ko16Bold.copyWith(color: WdColors.ink),
                    ),
                    Text(
                      '${(row.distanceMeters / 1000).toStringAsFixed(2)}km · ${formatRunTime(row.elapsed)} · '
                      '${formatRunPace(row.paceSecondsPerKm)}/km',
                      style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted),
                    ),
                  ],
                ),
              ),
              _resultTag(),
            ],
          ),
          Text(recordDate(row.startedAt), style: WdText.label12.copyWith(color: WdColors.muted)),
          if (course != null)
            Row(
              spacing: WdSpace.s8,
              children: [
                Expanded(
                  child: _CardButton('코스 상세', onTap: () => context.push(Routes.courseDetail(course.courseId))),
                ),
                Expanded(
                  child: _CardButton(
                    '리뷰 쓰기',
                    // 내 리뷰가 있으면 수정(B10), 쓸 수 있으면 작성(B2), 아니면 안내. 서버에 다시 물어 정한다
                    onTap: () => openReviewWriter(context, ref, courseId: course.courseId, courseName: course.courseName),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 아직 기기에만 있으면 동기화 대기(D-14). 코스 러닝은 완주 · 진행도, 자유 러닝은 기록.
  /// 고스트 대결의 대결 승 · 패는 고스트(F9)가 생기면 붙인다.
  Widget _resultTag() {
    final course = row.course;
    if (!row.synced) return const WdTag('동기화 대기', tone: WdTone.warning, filled: false);
    if (course == null) return const WdTag('기록', filled: false);
    if (course.completed) return const WdTag('완주', tone: WdTone.success, filled: false);
    return WdTag('${course.progressPercent.floor()}% 주행', filled: false);
  }
}

/// "09.08 (화)". 기록을 시작한 날(기기 시간대).
String recordDate(DateTime startedAt) {
  final t = startedAt.toLocal();
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')} (${weekdays[t.weekday - 1]})';
}

/// 카드 안 흰 버튼(Figma I1 [코스 상세] · [리뷰 쓰기]).
class _CardButton extends StatelessWidget {
  const _CardButton(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: WdSurface(
      color: WdColors.paper,
      padding: const EdgeInsets.symmetric(vertical: WdSpace.s10),
      onTap: onTap,
      child: Center(
        child: Text(label, style: WdText.raw(13, FontWeight.w600, 18).copyWith(color: WdColors.ink)),
      ),
    ),
  );
}
