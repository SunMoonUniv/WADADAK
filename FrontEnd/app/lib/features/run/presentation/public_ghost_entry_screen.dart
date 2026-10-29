import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../routes.dart';
import '../application/course_run_entry.dart';
import '../application/run_controller.dart';
import '../data/public_ghost_api.dart';
import '../domain/course_run.dart';
import '../domain/ghost_run.dart';
import '../domain/public_ghost.dart';

typedef PublicGhostArgs = ({
  CourseSelection course,
  String sourceId,
  String period,
});
final publicGhostSourceProvider = Provider<PublicGhostSource>(
  (ref) => PublicGhostApi(ref.watch(runControllerProvider).api),
);

/// Validates the selected public opponent, then enters the existing run preparation.
class PublicGhostEntryScreen extends ConsumerStatefulWidget {
  const PublicGhostEntryScreen({super.key, required this.args});
  final PublicGhostArgs args;

  @override
  ConsumerState<PublicGhostEntryScreen> createState() =>
      _PublicGhostEntryScreenState();
}

class _PublicGhostEntryScreenState
    extends ConsumerState<PublicGhostEntryScreen> {
  late final RunController runs;
  String? member, error;
  int epoch = 0;
  bool loading = true;
  bool get valid =>
      member != null && member == runs.currentOwner && runs.canSelectGhost;

  @override
  void initState() {
    super.initState();
    runs = ref.read(runControllerProvider)..addListener(changed);
    unawaited(load());
  }

  void changed() {
    if (!mounted || member == null || valid) return;
    epoch++;
    setState(() {
      loading = false;
      error = '계정 또는 진행 중인 러닝이 바뀌었어요. 코스 랭킹에서 다시 선택해 주세요.';
    });
  }

  Future<void> load() async {
    final version = ++epoch;
    member = null;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await runs.bindOwner();
      if (!mounted || version != epoch) return;
      member = runs.currentOwner;
      if (!valid) throw StateError('진행 중인 달리기를 먼저 확인해 주세요.');
      final owner = member!;
      final json = await ref
          .read(publicGhostSourceProvider)
          .prepare(
            owner,
            widget.args.sourceId,
            widget.args.course.courseId,
            widget.args.period,
          );
      final activeOwner = await runs.owner();
      if (!mounted || version != epoch || !valid || activeOwner != owner) {
        return;
      }
      final selected = PreparedPublicGhost(owner, json);
      if (selected.sourceId != widget.args.sourceId ||
          selected.course.id != widget.args.course.courseId ||
          selected.publicPeriod != widget.args.period) {
        throw const FormatException('선택한 공개 고스트가 바뀌었어요.');
      }
      runs.selectCourse(widget.args.course);
      final context = await runs.prepareGhostSelection();
      if (!mounted || version != epoch || !valid || context.owner != owner) {
        return;
      }
      if (context.snapshot.courseId != selected.course.id ||
          context.snapshot.version != selected.course.version ||
          context.snapshot.totalDistanceMeters !=
              selected.reference.totalDistanceMeters ||
          !GhostRunContext.sameRoute(context.snapshot, selected.reference)) {
        throw StateError('코스가 바뀌었어요. 공개 기록을 다시 선택해 주세요.');
      }
      runs.selectGhost(selected);
      ref.read(ghostTabProvider.notifier).set(true);
      ref.read(courseTabProvider.notifier).set(false);
      if (mounted) this.context.go(Routes.run);
    } on Object catch (e) {
      if (mounted && version == epoch) {
        error = e is ApiException
            ? e.message
            : '공개 기록을 사용할 수 없어요. 코스 랭킹에서 다시 선택해 주세요.';
      }
    } finally {
      if (mounted && version == epoch) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    epoch++;
    runs.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: WdAppBar(
      title: '고스트 대결 준비',
      onBack: () => context.canPop() ? context.pop() : context.go(Routes.run),
    ),
    body: Padding(
      padding: const EdgeInsets.all(WdSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: WdSpace.s16),
            const WdInfoBanner('선택한 공개 기록으로 대결을 준비하고 있어요.', plain: true),
          ],
          if (error != null) ...[
            WdInfoBanner(error!, tone: WdBannerTone.warning),
            const SizedBox(height: WdSpace.s16),
            WdButton('다시 확인', onPressed: loading || !valid ? null : load),
          ],
        ],
      ),
    ),
  );
}
