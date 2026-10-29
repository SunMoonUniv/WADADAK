import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../routes.dart';
import '../review/review_entry.dart';
import '../run/domain/run_models.dart';
import 'run_history_loader.dart';
import 'run_history_rows.dart';
import 'run_month_sheet.dart';

/// I1 · 내 러닝 기록 — 캘린더형(Figma `I1 · 내 러닝 기록 — 캘린더형 (10/27 회의)`). MY에서 연다(하단 탭이 보인다).
///
/// 위에서부터 유형 탭 · 전체 기간 요약 · 달력(달 이동 · 달린 날 도장) · "N월 분석" · 그 달 기록이다.
/// - 유형 탭(전체 · 자유 러닝 · 코스 러닝 · 고스트 대결)은 화면 전체에 적용한다.
/// - 달을 바꾸면(‹ › · 오늘 · 연월 고르기) 달력 · N월 분석 · 아래 기록만 바뀐다. 위쪽 요약은 늘 전체 기간이다.
/// - 합계는 앱이 낸다. 처음에 내 기록을 끝까지 받는다([AllRunHistory]).
/// - 칼로리는 계산식(달리기 담당)이 아직 없어 `—`다(정책 공통 9).
/// (2026-10-27 회의 · 사용자 결정)
///
/// 코스 러닝 기록의 [코스 상세]는 B1, [리뷰 쓰기]는 리뷰 진입(`openReviewWriter`)으로 간다.
class MyRunHistoryScreen extends ConsumerStatefulWidget {
  const MyRunHistoryScreen({super.key, this.now = DateTime.now});

  /// 오늘. 테스트에서 날짜를 고정한다.
  final DateTime Function() now;

  @override
  ConsumerState<MyRunHistoryScreen> createState() => _MyRunHistoryScreenState();
}

class _MyRunHistoryScreenState extends ConsumerState<MyRunHistoryScreen> with AllRunHistory {
  var _type = RunType.all;

  /// 달력 · N월 분석 · 아래 기록이 보는 달(1일). 처음은 이번 달이다.
  late DateTime _month = _thisMonth;

  DateTime get _thisMonth => DateTime(widget.now().year, widget.now().month);

  Future<void> _refresh() async {
    await runs.sync(manual: true);
    await runs.loadHistory(pageSize: AllRunHistory.pageSize);
  }

  Future<void> _pickMonth(DateTime first) async {
    final picked = await showRunMonthSheet(context, selected: _month, first: first, last: _thisMonth);
    if (picked != null && mounted) setState(() => _month = picked);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runs,
    builder: (context, _) {
      final all = allRuns;
      final rows = all.where(_type.includes).toList();
      final thisMonth = _thisMonth;
      // 가장 오래된 기록이 있는 달까지만 뒤로 갈 수 있다(기록이 없으면 이번 달만)
      final firstMonth = all.isEmpty
          ? thisMonth
          : DateTime(all.last.startedAt.toLocal().year, all.last.startedAt.toLocal().month);
      // 끝까지 받기 전에는 합계가 덜 나오므로 로딩으로 보인다
      final loading = loadingAllRuns;
      final monthRows = inMonth(rows, _month).toList();
      return DefaultTabController(
        length: RunType.values.length,
        child: Scaffold(
          backgroundColor: WdColors.paper,
          appBar: WdAppBar(title: '내 기록', onBack: () => context.pop()),
          body: Column(
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: WdColors.map))),
                child: WdTabBar(
                  // 고른 탭에만 개수를 붙인다(Figma "전체 42"). 다 받은 뒤에 보인다
                  tabs: [
                    for (final t in RunType.values) t == _type && !loading ? '${t.label} ${rows.length}' : t.label,
                  ],
                  onTap: (index) => setState(() => _type = RunType.values[index]),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: WdColors.ink,
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: WdSpace.s24),
                    children: [
                      _TotalSummary(totals: RunTotals.of(rows), loading: loading),
                      const ColoredBox(color: WdColors.soft, child: SizedBox(height: 8)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(WdSpace.s24, 18, WdSpace.s24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: WdSpace.s6,
                          children: [
                            _MonthNav(
                              month: _month,
                              onPrevious: _month.isAfter(firstMonth)
                                  ? () => setState(() => _month = DateTime(_month.year, _month.month - 1))
                                  : null,
                              onNext: _month.isBefore(thisMonth)
                                  ? () => setState(() => _month = DateTime(_month.year, _month.month + 1))
                                  : null,
                              onPick: () => _pickMonth(firstMonth),
                              onToday: () => setState(() => _month = thisMonth),
                            ),
                            _Calendar(month: _month, runDays: runDays(rows, _month), today: widget.now()),
                            const SizedBox(height: WdSpace.s10),
                            _MonthAnalysis(month: _month, totals: RunTotals.of(monthRows)),
                            const SizedBox(height: WdSpace.s16),
                            Text('상세 기록', style: WdText.ko16Bold.copyWith(color: WdColors.muted)),
                            if (runs.historyNotice != null) ...[
                              const WdInfoBanner(
                                '서버 기록을 불러오지 못했어요. 기기에 저장된 기록은 볼 수 있어요.',
                                tone: WdBannerTone.warning,
                              ),
                              TextButton(
                                onPressed: runs.loadingHistory
                                    ? null
                                    : () => runs.loadHistory(more: runs.nextCursor != null, pageSize: AllRunHistory.pageSize),
                                child: const Text('다시 불러오기'),
                              ),
                            ],
                            if (monthRows.isEmpty && !loading)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: WdSpace.s32),
                                child: Center(
                                  child: Text(_emptyText, style: WdText.label12.copyWith(color: WdColors.muted)),
                                ),
                              ),
                            for (final row in monthRows) ...[const SizedBox(height: WdSpace.s6), RunRecordCard(row)],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  String get _emptyText => _type == RunType.ghost ? '아직 고스트 대결 기록이 없어요.' : '이 달의 러닝 기록이 없어요.';
}

/// 위쪽 전체 기간 요약: 큰 거리 + 시간 · 페이스 · 칼로리.
class _TotalSummary extends StatelessWidget {
  const _TotalSummary({required this.totals, required this.loading});

  final RunTotals totals;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, 22),
    child: Column(
      spacing: WdSpace.s16,
      children: [
        Column(
          spacing: 2,
          children: [
            Text('전체 기간', style: WdText.raw(12, FontWeight.w700, 16).copyWith(color: WdColors.muted)),
            SizedBox(
              height: 56,
              child: loading
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(color: WdColors.ink, strokeWidth: 2),
                      ),
                    )
                  : Text(
                      (totals.distanceMeters / 1000).toStringAsFixed(2),
                      style: WdText.raw(48, FontWeight.w700, 56).copyWith(color: WdColors.ink),
                    ),
            ),
            Text('거리(km)', style: WdText.raw(12, FontWeight.w500, 16).copyWith(color: WdColors.muted)),
          ],
        ),
        IntrinsicHeight(
          child: Row(
            children: [
              _metric(loading ? '—' : formatRunTime(totals.elapsed), '시간'),
              const VerticalDivider(width: 1, thickness: 1, color: WdColors.map, indent: 6, endIndent: 6),
              _metric(loading ? '—' : formatRunPace(totals.paceSecondsPerKm), '페이스'),
              const VerticalDivider(width: 1, thickness: 1, color: WdColors.map, indent: 6, endIndent: 6),
              // 칼로리 계산식은 달리기 담당이 정한다(정책 공통 9). 아직 없어서 비워 둔다
              _metric('—', '칼로리(kcal)'),
            ],
          ),
        ),
      ],
    ),
  );

  static Widget _metric(String value, String label) => Expanded(
    child: Column(
      spacing: 2,
      children: [
        Text(value, style: WdText.raw(20, FontWeight.w700, 26).copyWith(color: WdColors.ink)),
        Text(label, style: WdText.raw(12, FontWeight.w500, 16).copyWith(color: WdColors.muted)),
      ],
    ),
  );
}

/// "‹ 2026.10 ›" + 오늘. 달 이름을 누르면 연 · 월을 고른다. 이번 달보다 뒤나 첫 기록보다 앞으로는 못 간다.
class _MonthNav extends StatelessWidget {
  const _MonthNav({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback? onPrevious, onNext;
  final VoidCallback onPick, onToday;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(width: 40),
      Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: WdSpace.s6,
          children: [
            _arrow('‹', '이전 달', onPrevious),
            Semantics(
              button: true,
              label: '연 · 월 고르기',
              child: InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(WdRadius.r8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WdSpace.s6, vertical: WdSpace.s4),
                  child: Text(
                    '${month.year}.${month.month.toString().padLeft(2, '0')}',
                    style: WdText.raw(20, FontWeight.w700, 26).copyWith(color: WdColors.ink),
                  ),
                ),
              ),
            ),
            _arrow('›', '다음 달', onNext),
          ],
        ),
      ),
      SizedBox(
        width: 40,
        child: InkWell(
          onTap: onToday,
          child: Text(
            '오늘',
            textAlign: TextAlign.right,
            style: WdText.raw(13, FontWeight.w700, 20).copyWith(color: WdColors.green),
          ),
        ),
      ),
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
            style: WdText.raw(22, FontWeight.w400, 28).copyWith(color: onTap == null ? WdColors.grayLight : WdColors.muted),
          ),
        ),
      ),
    ),
  );
}

/// 일요일부터 시작하는 6주 달력. 달린 날은 연두 도장, 오늘은 테두리, 앞뒤 달 날짜는 흐리게.
class _Calendar extends StatelessWidget {
  const _Calendar({required this.month, required this.runDays, required this.today});

  final DateTime month;
  final Set<int> runDays;
  final DateTime today;

  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    // 1일이 무슨 요일인지에 따라 앞 달 날짜를 채운다(일요일 0)
    final leading = DateTime(month.year, month.month).weekday % 7;
    final days = [for (var i = 0; i < 42; i++) DateTime(month.year, month.month, 1 - leading + i)];
    return Column(
      children: [
        Row(
          children: [
            for (final d in _weekdays)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: WdSpace.s8, bottom: WdSpace.s6),
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: WdText.raw(12, FontWeight.w500, 16).copyWith(color: WdColors.muted),
                  ),
                ),
              ),
          ],
        ),
        for (var w = 0; w < 6; w++)
          Row(children: [for (final day in days.skip(w * 7).take(7)) Expanded(child: _cell(day))]),
      ],
    );
  }

  Widget _cell(DateTime day) {
    final inMonth = day.month == month.month;
    final ran = inMonth && runDays.contains(day.day);
    final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
    final label = Text(
      '${day.day}',
      style: WdText.raw(14, ran || isToday ? FontWeight.w700 : FontWeight.w500, 18)
          .copyWith(color: inMonth ? WdColors.ink : WdColors.grayLight),
    );
    return SizedBox(
      height: 46,
      child: Center(
        child: Semantics(
          label: ran ? '${day.month}월 ${day.day}일 달림' : null,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: ran
                ? const BoxDecoration(color: WdColors.lime, shape: BoxShape.circle)
                : isToday
                ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: WdColors.ink, width: 1.5))
                : null,
            child: label,
          ),
        ),
      ),
    );
  }
}

/// "10월 분석" 카드: 그 달 거리 / 시간 / 페이스 / 칼로리.
class _MonthAnalysis extends StatelessWidget {
  const _MonthAnalysis({required this.month, required this.totals});

  final DateTime month;
  final RunTotals totals;

  @override
  Widget build(BuildContext context) => WdSurface(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: WdSpace.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WdSpace.s4,
      children: [
        Text('${month.month}월 분석', style: WdText.raw(15, FontWeight.w700, 22).copyWith(color: WdColors.ink)),
        Text(
          '${(totals.distanceMeters / 1000).toStringAsFixed(2)}km  /  ${formatRunTime(totals.elapsed)}  /  '
          '${formatRunPace(totals.paceSecondsPerKm)}  /  —kcal',
          style: WdText.raw(14, FontWeight.w500, 20).copyWith(color: WdColors.green),
        ),
      ],
    ),
  );
}

/// Figma I1 기록 줄: 요일 · 날짜 | 제목(코스 이름 또는 자유 러닝 · 고스트 대결) · 시간 · 거리 · 페이스 | 결과 태그.
/// 코스 러닝이면 아래에 [코스 상세] · [리뷰 쓰기]. 누르면 기록 상세.
class RunRecordCard extends ConsumerWidget {
  const RunRecordCard(this.row, {super.key});

  final RunHistoryRow row;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = row.course;
    final started = row.startedAt.toLocal();
    return WdSurface(
      padding: const EdgeInsets.symmetric(horizontal: WdSpace.s16, vertical: WdSpace.s14),
      onTap: () => context.push(Routes.myRecord(row.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WdSpace.s12,
        children: [
          Row(
            spacing: WdSpace.s14,
            children: [
              Column(
                children: [
                  Text(
                    _weekdays[started.weekday - 1],
                    style: WdText.raw(11, FontWeight.w700, 16).copyWith(color: WdColors.green),
                  ),
                  Text('${started.day}', style: WdText.raw(22, FontWeight.w700, 26).copyWith(color: WdColors.green)),
                ],
              ),
              const SizedBox(height: 34, child: VerticalDivider(width: 1, thickness: 1, color: WdColors.map)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      // 아직 올리지 않은 기록은 코스 판정 전이라 자유 러닝인지 모른다
                      course?.courseName ?? (row.ghost != null ? '고스트 대결' : row.synced ? '자유 러닝' : '러닝'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WdText.raw(15, FontWeight.w700, 22).copyWith(color: WdColors.ink),
                    ),
                    Text(
                      '${formatRunTime(row.elapsed)} · ${(row.distanceMeters / 1000).toStringAsFixed(2)}km · '
                      '${formatRunPace(row.paceSecondsPerKm)}/km',
                      style: WdText.raw(12, FontWeight.w400, 18).copyWith(color: WdColors.muted),
                    ),
                  ],
                ),
              ),
              _resultTag(),
            ],
          ),
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

  /// 아직 기기에만 있으면 동기화 대기(D-14). 고스트 대결은 서버 판정(승리 · 패배 · 무승부 · 대결 무효),
  /// 코스 러닝은 완주 · 진행도, 자유 러닝은 기록.
  Widget _resultTag() {
    final course = row.course;
    final ghost = row.ghost;
    if (!row.synced) return const WdTag('동기화 대기', tone: WdTone.warning, filled: false);
    if (ghost != null) {
      return WdTag(
        ghost.label,
        tone: switch (ghost.outcome) {
          'WIN' => WdTone.success,
          'INVALID' => WdTone.warning,
          _ => WdTone.neutral,
        },
        filled: false,
      );
    }
    if (course == null) return const WdTag('기록', filled: false);
    if (course.completed) return const WdTag('완주', tone: WdTone.success, filled: false);
    return WdTag('${course.progressPercent.floor()}% 주행', filled: false);
  }
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
        child: Text(label, style: WdText.raw(13, FontWeight.w500, 18).copyWith(color: WdColors.ink)),
      ),
    ),
  );
}
