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
import 'free_ghost_record_choice.dart';
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
  Timer? selectionDeadline;

  void cancelSelectionDeadline() {
    selectionDeadline?.cancel();
    selectionDeadline = null;
  }

  @override
  void initState() {
    super.initState();
    runs = ref.read(runControllerProvider)..addListener(changed);
    unawaited(load());
  }

  void changed() {
    if (owner != null && (owner != runs.currentOwner || !runs.canSelectGhost)) {
      cancelSelectionDeadline();
      epoch++;
      selecting = null;
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
    cancelSelectionDeadline();
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
    if (!c.distanceEligible || loading || owner == null || selecting != null) {
      return;
    }
    final token = ++epoch;
    setState(() {
      selecting = c.id;
      prepared = null;
      error = null;
    });
    selectionDeadline = Timer(freeGhostPreparationTimeout, () {
      if (!valid(token)) return;
      // Invalidate a late response before allowing another selection.
      epoch++;
      selectionDeadline = null;
      setState(() {
        selecting = null;
        prepared = null;
        error = freeGhostPreparationTimeoutError.message;
      });
    });
    try {
      final j = await ref.read(freeGhostSourceProvider).prepare(owner!, c.id);
      if (!valid(token)) return;
      final replay = (j['playback'] as Map);
      if (replay['eligible'] != true) {
        throw StateError(freeGhostUnavailableMessage(j));
      }
      final p = PreparedFreeGhost(owner!, j, startedAt: c.startedAt);
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
      if (mounted && token == epoch) {
        cancelSelectionDeadline();
        setState(() => selecting = null);
      }
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
    cancelSelectionDeadline();
    epoch++;
    runs.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = prepared;
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(title: '내 자유러닝 기록', onBack: back),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          const Text('어느 날의 나와 달릴까요?', style: WdText.ko22Bold),
          const SizedBox(height: 4),
          Text(
            '대결할 자유러닝 기록을 골라 주세요.',
            style: WdText.ko12.copyWith(color: WdColors.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
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
          const SizedBox(height: 20),
          const WdSectionHeading('내 자유러닝 기록', actionLabel: '최근 달린 순'),
          const SizedBox(height: 12),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (rows.isEmpty && error == null)
            const WdInfoBanner('저장된 자유 러닝 기록이 없어요. 서버 동기화를 확인해 주세요.')
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              FreeGhostRecordChoice(
                key: ValueKey('free-ghost-record-${rows[i].id}'),
                record: rows[i],
                prepared: p,
                checking: selecting == rows[i].id,
                onTap: rows[i].distanceEligible && selecting == null && !loading
                    ? () => select(rows[i])
                    : null,
              ),
            ],
          if (cursor != null)
            WdButton(
              more ? '불러오는 중' : '기록 더 보기',
              variant: WdButtonVariant.secondary,
              onPressed: more ? null : () => load(append: true),
            ),
          if (error != null) ...[
            const SizedBox(height: 12),
            WdInfoBanner(error!, tone: WdBannerTone.warning),
            WdButton(
              '다시 불러오기',
              variant: WdButtonVariant.secondary,
              onPressed: () => load(),
            ),
          ],
          const SizedBox(height: 16),
          Text(p == null ? '경로 미리보기' : '선택한 기록의 경로', style: WdText.ko14Bold),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: p == null
                  ? WdSurface(
                      color: WdColors.map,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8,
                          children: [
                            const WdIcon(WdIcons.ghostInfo, size: 24),
                            Text(
                              '기록을 고르면 경로를 확인할 수 있어요.',
                              style: WdText.ko12.copyWith(
                                color: WdColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : MapView(
                      initialCenter: p.reference.route.first,
                      lines: [
                        for (
                          var i = 0;
                          i < p.reference.routeSegments.length;
                          i++
                        )
                          MapLine(
                            id: 'reference-$i',
                            points: p.reference.routeSegments[i],
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          if (p == null)
            Text(
              '1km 이상이며 경로를 재생할 수 있는 기록을 선택해요.',
              style: WdText.ko12.copyWith(color: WdColors.muted),
            )
          else ...[
            Text(
              '대결 비교 시간',
              style: WdText.ko12.copyWith(color: WdColors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              '${(p.originalDistanceM / 1000).toStringAsFixed(2)} km · ${formatRunTime(Duration(seconds: p.replay.seconds))}',
              style: WdText.ko14Bold.copyWith(color: WdColors.green),
            ),
            const SizedBox(height: 4),
            Text(
              '원래 기록 ${formatRunTime(Duration(milliseconds: p.originalElapsedMs))}',
              style: WdText.ko12.copyWith(color: WdColors.muted),
            ),
            const SizedBox(height: 8),
            const WdInfoBanner(
              '같은 완주 기준까지 비교해요. 중단된 기록도 재생할 수 있으면 선택할 수 있고, 원래 기록은 그대로 보존돼요.',
              plain: true,
            ),
          ],
        ],
      ),
      bottomNavigationBar: WdBottomBar.pinned(
        primary: WdButton(
          '이 기록 선택하기',
          onPressed: p == null || !runs.canSelectGhost
              ? null
              : () {
                  if (owner != runs.currentOwner) return;
                  runs.selectFreeGhost(p);
                  ref
                      .read(ghostRecordKindProvider.notifier)
                      .set(GhostRecordKind.personal);
                  ref.read(ghostTabProvider.notifier).set(true);
                  ref.read(courseTabProvider.notifier).set(false);
                  back();
                },
        ),
      ),
    );
  }
}
