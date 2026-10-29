import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../core/map/map_view.dart';
import '../../../routes.dart';
import '../application/course_run_entry.dart';
import '../application/run_controller.dart';
import '../data/free_ghost_api.dart';
import '../domain/free_ghost.dart';
import 'free_ghost_unavailable.dart';
import '../domain/run_models.dart';

final freeGhostSourceProvider = Provider<FreeGhostSource>(
  (ref) => FreeGhostApi(ref.watch(runControllerProvider).api),
);

/// C9 components, with no cross-route best/average ranking for free records.
class FreeGhostSelectionScreen extends ConsumerStatefulWidget {
  const FreeGhostSelectionScreen({super.key});
  @override
  ConsumerState<FreeGhostSelectionScreen> createState() =>
      _FreeGhostSelectionScreenState();
}

class _FreeGhostSelectionScreenState
    extends ConsumerState<FreeGhostSelectionScreen> {
  late final RunController runs;
  List<FreeGhostCandidate> rows = [];
  String? owner, cursor, error, selecting;
  String period = 'ALL';
  PreparedFreeGhost? prepared;
  bool loading = true, more = false;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    runs = ref.read(runControllerProvider)..addListener(changed);
    unawaited(load());
  }

  void changed() {
    if (owner != null && (owner != runs.currentOwner || !runs.canSelectGhost)) {
      epoch++;
      prepared = null;
      rows = [];
      owner = null;
      if (mounted) {
        setState(() {
          error = '계정이나 달리기 상태가 바뀌었어요. 준비 화면에서 다시 선택해 주세요.';
          loading = false;
        });
      }
    }
  }

  bool valid(int token) =>
      mounted &&
      token == epoch &&
      owner == runs.currentOwner &&
      runs.canSelectGhost;
  Future<void> load({bool append = false}) async {
    if (append && (more || cursor == null)) return;
    final token = ++epoch;
    setState(() {
      error = null;
      prepared = null;
      selecting = null;
      if (append) {
        more = true;
      } else {
        loading = true;
        rows = [];
        cursor = null;
      }
    });
    try {
      await runs.bindOwner();
      if (!mounted || token != epoch) return;
      owner = runs.currentOwner;
      if (owner == null || !runs.canSelectGhost) {
        throw StateError('달리기 준비 화면에서 다시 선택해 주세요.');
      }
      final next = await ref
          .read(freeGhostSourceProvider)
          .candidates(owner!, period: period, cursor: append ? cursor : null);
      if (!valid(token)) return;
      if (append && next.nextCursor == cursor) {
        throw const FormatException('Repeated cursor');
      }
      final ids = rows.map((r) => r.id).toSet();
      rows = [...rows, ...next.content.where((r) => ids.add(r.id))];
      cursor = next.nextCursor;
    } catch (e) {
      if (mounted && token == epoch) {
        error = e is ApiException ? e.message : '기록을 불러오지 못했어요. 다시 시도해 주세요.';
      }
    } finally {
      if (mounted && token == epoch) {
        setState(() {
          loading = false;
          more = false;
        });
      }
    }
  }

  Future<void> select(FreeGhostCandidate c) async {
    if (!c.distanceEligible || loading || owner == null) return;
    final token = ++epoch;
    setState(() {
      selecting = c.id;
      prepared = null;
      error = null;
    });
    try {
      final j = await ref.read(freeGhostSourceProvider).prepare(owner!, c.id);
      if (!valid(token)) return;
      final replay = (j['playback'] as Map);
      if (replay['eligible'] != true) {
        throw StateError(freeGhostUnavailableMessage(j));
      }
      final p = PreparedFreeGhost(owner!, j);
      if (p.replay.sourceId != c.id ||
          p.originalDistanceM != c.distanceM ||
          p.originalElapsedMs != c.elapsedMs) {
        throw const FormatException('Source mismatch');
      }
      prepared = p;
    } catch (e) {
      if (valid(token)) {
        error = e is ApiException
            ? e.message
            : e is StateError
            ? e.message.toString()
            : '기록을 확인하지 못했어요. 다시 선택해 주세요.';
      }
    } finally {
      if (mounted && token == epoch) setState(() => selecting = null);
    }
  }

  void back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.run);
    }
  }

  @override
  void dispose() {
    epoch++;
    runs.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = prepared;
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(title: '내 자유 기록 선택', onBack: back),
      body: ListView(
        padding: const EdgeInsets.all(WdSpace.s24),
        children: [
          Wrap(
            spacing: WdSpace.s6,
            children: [
              for (final option in [
                ('ALL', '전체 기간'),
                ('MONTH', '이번 달'),
                ('WEEK', '이번 주'),
              ])
                WdFilterChip(
                  option.$2,
                  selected: period == option.$1,
                  onTap: () {
                    period = option.$1;
                    unawaited(load());
                  },
                ),
            ],
          ),
          const SizedBox(height: WdSpace.s16),
          const WdInfoBanner(
            '1km 이상 달린 내 자유 기록을 골라 같은 경로로 대결해요. 중단된 기록도 재생할 수 있으면 선택할 수 있어요.',
            plain: true,
          ),
          const SizedBox(height: WdSpace.s16),
          const WdSectionHeading('내 자유 기록', actionLabel: '최근 달린 순'),
          const SizedBox(height: WdSpace.s12),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (rows.isEmpty && error == null)
            const WdInfoBanner('저장된 자유 러닝 기록이 없어요. 서버 동기화를 확인해 주세요.')
          else
            WdSurface(
              padding: const EdgeInsets.symmetric(horizontal: WdSpace.s12),
              child: Column(
                children: [
                  for (final c in rows)
                    Semantics(
                      enabled: c.distanceEligible,
                      child: Opacity(
                        opacity: c.distanceEligible ? 1 : 0.5,
                        child: WdRankRow(
                          WdRank(
                            rank: p?.replay.sourceId == c.id ? '✓' : '',
                            name: date(c.startedAt),
                            meta: !c.distanceEligible
                                ? '1km 미만 · 선택 불가'
                                : '${(c.distanceM / 1000).toStringAsFixed(2)}km · ${c.endReason == 'USER' ? '종료 기록' : '중단 기록'}',
                            value: selecting == c.id
                                ? '확인 중'
                                : formatRunTime(
                                    Duration(milliseconds: c.elapsedMs),
                                  ),
                          ),
                          onTap: c.distanceEligible ? () => select(c) : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (cursor != null)
            WdButton(
              more ? '불러오는 중' : '기록 더 보기',
              variant: WdButtonVariant.secondary,
              onPressed: more ? null : () => load(append: true),
            ),
          if (error != null) ...[
            const SizedBox(height: WdSpace.s12),
            WdInfoBanner(error!, tone: WdBannerTone.warning),
            WdButton(
              '다시 불러오기',
              variant: WdButtonVariant.secondary,
              onPressed: () => load(),
            ),
          ],
          if (p != null) ...[
            const SizedBox(height: WdSpace.s16),
            WdRecordCard(
              overline: '대결 비교 시간',
              title: '선택한 내 자유 기록',
              time: formatRunTime(Duration(seconds: p.replay.seconds)),
              caption:
                  '원래 기록 ${formatRunTime(Duration(milliseconds: p.originalElapsedMs))}',
              footer: '같은 완주 기준까지 비교 · 원래 기록은 보존해요',
            ),
            const SizedBox(height: WdSpace.s12),
            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WdRadius.r12),
                child: MapView(
                  initialCenter: p.reference.route.first,
                  lines: [
                    for (var i = 0; i < p.reference.routeSegments.length; i++)
                      MapLine(
                        id: 'reference-$i',
                        points: p.reference.routeSegments[i],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(WdSpace.s16),
        child: WdButton(
          '이 기록과 대결하기',
          onPressed: p == null || !runs.canSelectGhost
              ? null
              : () {
                  if (owner != runs.currentOwner) return;
                  runs.selectFreeGhost(p);
                  ref.read(ghostTabProvider.notifier).set(true);
                  ref.read(courseTabProvider.notifier).set(false);
                  back();
                },
        ),
      ),
    );
  }

  static String date(DateTime t) {
    final k = t.toUtc().add(const Duration(hours: 9));
    return '${k.year}.${k.month.toString().padLeft(2, '0')}.${k.day.toString().padLeft(2, '0')}';
  }
}
