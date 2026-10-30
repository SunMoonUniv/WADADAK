import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/api/api_client.dart';
import '../../../routes.dart';
import '../application/course_run_entry.dart';
import '../application/ghost_retry_preparation.dart';
import '../application/run_controller.dart';
import '../data/ghost_comparison_api.dart';
import '../domain/ghost_comparison.dart';
import '../domain/run_models.dart';
import 'ghost_result_screen.dart';

final ghostComparisonSourceProvider = Provider<GhostComparisonSource>(
  (ref) => GhostComparisonApi(ref.watch(runControllerProvider).api),
);

class GhostResultEntryScreen extends ConsumerStatefulWidget {
  const GhostResultEntryScreen({
    super.key,
    required this.run,
    this.onRetryPending,
  });
  final RunSnapshot run;
  final VoidCallback? onRetryPending;
  @override
  ConsumerState<GhostResultEntryScreen> createState() =>
      _GhostResultEntryScreenState();
}

class _GhostResultEntryScreenState
    extends ConsumerState<GhostResultEntryScreen> {
  late final RunController _runs;
  String? _owner, _error;
  GhostComparison? _comparison;
  bool _loading = true, _preparing = false, _accountChanged = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    _runs = ref.read(runControllerProvider)..addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (_owner != null && _owner != _runs.currentOwner && mounted) {
      _epoch++;
      setState(() {
        _comparison = null;
        _loading = false;
        _preparing = false;
        _accountChanged = true;
      });
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _runs.bindOwner();
      if (!mounted || epoch != _epoch || _accountChanged) return;
      final owner = _runs.currentOwner;
      if (owner == null) throw StateError('로그인한 계정을 확인해 주세요.');
      _owner = owner;
      final detail = await ref
          .read(ghostComparisonSourceProvider)
          .get(owner, widget.run.sessionId!);
      final activeOwner = await _runs.owner();
      if (!mounted ||
          epoch != _epoch ||
          activeOwner != owner ||
          _runs.currentOwner != owner) {
        return;
      }
      final previous = widget.run.ghost;
      if (detail.sessionId != widget.run.sessionId ||
          previous != null &&
              (detail.sourceId != previous['sourceRecordId'] ||
                  detail.result['outcome'] != previous['outcome'] ||
                  detail.result['courseElapsedSeconds'] !=
                      previous['courseElapsedSeconds'] ||
                  detail.result['sourceElapsedSeconds'] !=
                      previous['sourceElapsedSeconds'])) {
        throw const FormatException('Mismatched saved verdict');
      }
      _comparison = detail;
    } on Object catch (e) {
      if (mounted && epoch == _epoch) {
        _error = e is ApiException
            ? e.message
            : '상세 비교를 확인하지 못했어요. 다시 시도해 주세요.';
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  bool get _canRetry =>
      !_runs.preparing &&
      !_runs.recorder.active &&
      !_runs.hasPendingGhostStart &&
      _runs.courseStart == null &&
      (_runs.run == null || _runs.run!.id == widget.run.sessionId);
  Future<void> _again() async {
    final detail = _comparison, owner = _owner;
    if (_preparing || detail == null || owner == null || !_canRetry) return;
    final epoch = ++_epoch;
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final prepared = await GhostRetryPreparation(_runs.api)
          .prepare(owner, detail);
      final activeOwner = await _runs.owner();
      if (!mounted ||
          epoch != _epoch ||
          activeOwner != owner ||
          _runs.currentOwner != owner ||
          !_canRetry) {
        return;
      }
      // No await between these mutations: another run can never be cleared by a late response.
      if (_runs.run != null) _runs.clearResult();
      _runs.clearCourse();
      if (prepared.free != null) _runs.selectFreeGhost(prepared.free!);
      if (prepared.course != null) _runs.selectGhost(prepared.course!);
      ref
          .read(ghostRecordKindProvider.notifier)
          .set(
            prepared.free != null
                ? GhostRecordKind.personal
                : GhostRecordKind.course,
          );
      ref.read(ghostTabProvider.notifier).set(true);
      ref.read(courseTabProvider.notifier).set(false);
      if (mounted) {
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          router.go(Routes.run);
        } else {
          Navigator.pop(context);
        }
      }
    } on Object catch (e) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = e is TimeoutException
              ? '고스트 확인이 15초 안에 끝나지 않았어요. 다시 시도해 주세요.'
              : e is ApiException
              ? e.message
              : '같은 고스트를 사용할 수 없어요. 원본과 코스의 공개 상태·경로를 확인하거나 다른 기록을 선택해 주세요.',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _preparing = false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    _runs.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_accountChanged) {
      return Scaffold(
        appBar: WdAppBar(title: '대결 결과', onBack: () => Navigator.pop(context)),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text('계정이 바뀌었어요. 내 기록에서 다시 열어 주세요.'),
        ),
      );
    }
    return GhostResultScreen(
      run: widget.run,
      comparison: _comparison,
      loading: _loading,
      error: _error,
      onRetry: _preparing
          ? null
          : () {
              widget.onRetryPending?.call();
              unawaited(_load());
            },
      onAgain: _comparison?.available == true && !_loading && _canRetry
          ? _again
          : null,
      preparing: _preparing,
    );
  }
}
