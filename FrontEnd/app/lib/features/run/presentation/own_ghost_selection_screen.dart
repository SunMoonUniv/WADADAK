import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../routes.dart';
import '../application/course_run_entry.dart';
import '../application/own_ghost_controller.dart';
import '../application/run_controller.dart';
import '../data/own_ghost_api.dart';
import '../domain/course_run.dart';
import '../domain/own_ghost.dart';
import 'own_ghost_selection_view.dart';

final ownGhostSourceProvider = Provider<OwnGhostSource>(
  (ref) => OwnGhostApi(ref.watch(runControllerProvider).api),
);

/// Own-record entry only. Public ranking CTAs keep their separate public-opponent contract.
class OwnGhostSelectionScreen extends ConsumerStatefulWidget {
  const OwnGhostSelectionScreen({super.key});

  @override
  ConsumerState<OwnGhostSelectionScreen> createState() =>
      _OwnGhostSelectionScreenState();
}

class _OwnGhostSelectionScreenState
    extends ConsumerState<OwnGhostSelectionScreen> {
  late final RunController _runs;
  OwnGhostController? _choices;
  CourseSelection? _course;
  String? _owner, _error;
  bool _loading = true;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _runs = ref.read(runControllerProvider)..addListener(_onRunChanged);
    unawaited(_load());
  }

  bool get _valid =>
      _runs.canSelectGhost &&
      _owner == _runs.currentOwner &&
      identical(_course, _runs.selectedCourse);

  void _onRunChanged() {
    if (_owner == null || _valid || !mounted) return;
    _epoch++;
    _choices?.dispose();
    _choices = null;
    _owner = null;
    setState(() {
      _loading = false;
      _error = '계정이나 코스가 바뀌었어요. 달리기 준비에서 다시 선택해 주세요.';
    });
    if (!_runs.canSelectGhost) _returnToRun();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    _choices?.dispose();
    _choices = null;
    _owner = null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _runs.bindOwner();
      if (!mounted || epoch != _epoch) return;
      if (!_runs.canSelectGhost) {
        _returnToRun();
        return;
      }
      final prepared = await _runs.prepareGhostSelection();
      if (!mounted || epoch != _epoch) return;
      _course = _runs.selectedCourse;
      _owner = prepared.owner;
      final choices = OwnGhostController(
        ref.read(ownGhostSourceProvider),
        owner: prepared.owner,
        course: GhostCourseContext(
          prepared.snapshot.courseId!,
          prepared.snapshot.version!,
        ),
      );
      _choices = choices;
      await choices.load();
    } on Object catch (error) {
      if (!mounted || epoch != _epoch) return;
      _error = error is ApiException
          ? error.message
          : '코스를 확인하지 못했어요. 달리기 준비에서 코스를 확인하고 다시 시도해 주세요.';
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.run);
    }
  }

  void _returnToRun() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(Routes.run);
    });
  }

  void _select(PreparedOwnGhost prepared) {
    if (!_valid || !identical(prepared, _choices?.prepared)) return;
    _runs.selectGhost(prepared);
    ref.read(ghostTabProvider.notifier).set(true);
    ref.read(courseTabProvider.notifier).set(false);
    _back();
  }

  @override
  void dispose() {
    _epoch++;
    _runs.removeListener(_onRunChanged);
    _choices?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    if (!_loading && choices != null && _valid) {
      return OwnGhostSelectionView(
        controller: choices,
        courseName: _course!.name,
        onBack: _back,
        onPrepared: _select,
      );
    }
    return Scaffold(
      backgroundColor: WdColors.paper,
      appBar: WdAppBar(title: '고스트 선택', onBack: _back),
      body: Padding(
        padding: const EdgeInsets.all(WdSpace.s24),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WdInfoBanner(
                    _error ?? '달리기 준비에서 코스를 먼저 골라 주세요.',
                    tone: WdBannerTone.warning,
                  ),
                  const SizedBox(height: WdSpace.s16),
                  if (_runs.canSelectGhost && _runs.selectedCourse != null)
                    WdButton('다시 시도', onPressed: _load),
                  WdButton(
                    '달리기 준비로',
                    variant: WdButtonVariant.secondary,
                    onPressed: _back,
                  ),
                ],
              ),
      ),
    );
  }
}
