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
/// 지금은 "최근 기록" 목록만 있다. 유형 탭 · 월 요약 · 주간 주행 거리 · 필터는 다음에 붙인다.
/// 코스 러닝 카드의 [코스 상세]는 B1, [리뷰 쓰기]는 리뷰 진입(`openReviewWriter`)으로 간다.
/// 기록 데이터(기기 · 서버 · 동기화 · 삭제)는 달리기 담당의 `runController`를 그대로 쓴다.
class MyRunHistoryScreen extends ConsumerStatefulWidget {
  const MyRunHistoryScreen({super.key});

  @override
  ConsumerState<MyRunHistoryScreen> createState() => _MyRunHistoryScreenState();
}

class _MyRunHistoryScreenState extends ConsumerState<MyRunHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final c = ref.read(runControllerProvider);
      await c.bindOwner();
      if (mounted) unawaited(c.loadHistory());
    });
  }

  Future<void> _refresh() async {
    final c = ref.read(runControllerProvider);
    await c.sync(manual: true);
    await c.loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(runControllerProvider);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final rows = runHistoryRows(local: c.records, remote: c.remoteRecords, deletedIds: c.deletedIds);
        return Scaffold(
          backgroundColor: WdColors.paper,
          appBar: WdAppBar(title: '내 기록', onBack: () => context.pop()),
          body: RefreshIndicator(
            color: WdColors.ink,
            onRefresh: _refresh,
            child: NotificationListener<ScrollNotification>(
              // 끝에서 400px 안으로 내려오면 이전 기록을 더 받는다
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 400 &&
                    notification is ScrollUpdateNotification &&
                    notification.metrics.axisDirection == AxisDirection.down) {
                  unawaited(c.loadHistory(more: true));
                }
                return false;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(WdSpace.s24, WdSpace.s20, WdSpace.s24, WdSpace.s24),
                children: [
                  Text('최근 기록', style: WdText.ko16Bold.copyWith(color: WdColors.ink)),
                  if (c.historyNotice != null) ...[
                    const SizedBox(height: WdSpace.s12),
                    const WdInfoBanner('서버 기록을 불러오지 못했어요. 기기에 저장된 기록은 볼 수 있어요.', tone: WdBannerTone.warning),
                    TextButton(
                      onPressed: c.loadingHistory ? null : () => c.loadHistory(),
                      child: const Text('다시 불러오기'),
                    ),
                  ],
                  if (rows.isEmpty && !c.loadingHistory)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: WdSpace.s56),
                      child: Center(
                        child: Text(
                          '아직 러닝 기록이 없어요. 첫 러닝을 시작해 보세요.',
                          style: WdText.label12.copyWith(color: WdColors.muted),
                        ),
                      ),
                    ),
                  for (final row in rows) ...[const SizedBox(height: WdSpace.s12), RunRecordCard(row)],
                  if (c.loadingHistory)
                    const Padding(
                      padding: EdgeInsets.all(WdSpace.s16),
                      child: Center(child: CircularProgressIndicator(color: WdColors.ink)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
