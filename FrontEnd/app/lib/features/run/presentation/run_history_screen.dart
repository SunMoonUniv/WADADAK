import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../routes.dart';
import '../application/free_run_controller.dart';
import '../application/run_controller.dart';
import '../domain/recording_models.dart' as recording;
import '../application/run_result_mapper.dart';
export '../application/run_result_mapper.dart' show remoteRunSnapshot;
import '../domain/run_models.dart';
import 'free_run_result_view.dart';

class RunHistoryScreen extends ConsumerStatefulWidget {
  const RunHistoryScreen({super.key, this.myTab = false});
  final bool myTab;
  @override
  ConsumerState<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends ConsumerState<RunHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final c = ref.read(runControllerProvider);
      await c.bindOwner();
      if (mounted) unawaited(c.loadHistory());
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(runControllerProvider);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final local = {for (final r in c.records) r.id: r};
        final rows =
            <Map<String, dynamic>>[
              for (final r in c.records)
                {
                  'id': r.id,
                  'startedAt': r.startedAt.toIso8601String(),
                  'metrics':
                      r.result?['metrics'] ??
                      recording.RunCalculator.replay(r.inputs)
                          .at(r.checkpointMs)
                          .toJson(),
                  'syncState': r.syncState,
                },
              for (final r in c.remoteRecords)
                if (!local.containsKey(r['id']) &&
                    !c.deletedIds.contains(r['id']))
                  {...r, 'syncState': 'synced'},
            ]..sort(
              (a, b) =>
                  DateTime.parse(b['startedAt'] as String)
                      .compareTo(DateTime.parse(a['startedAt'] as String)),
            );
        return Scaffold(
          backgroundColor: WdColors.paper,
          appBar: WdAppBar(
            title: widget.myTab ? 'MY · 러닝 기록' : '러닝 기록',
            onBack: widget.myTab ? null : () => Navigator.pop(context),
            action: WdAppBarAction.circle(
              WdIcons.settings,
              semanticLabel: '러닝 설정',
              onTap: () => context.push(Routes.runSettings),
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await c.sync(manual: true);
              await c.loadHistory();
            },
            child: ListView(
              padding: const EdgeInsets.all(WdSpace.s24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '내 러닝 ${rows.length}개',
                        style: WdText.ko20Bold,
                      ),
                    ),
                    TextButton(
                      onPressed: c.syncing
                          ? null
                          : () async {
                              await c.sync(manual: true);
                              await c.loadHistory();
                            },
                      child: Text(c.syncing ? '동기화 중' : '동기화'),
                    ),
                  ],
                ),
                if (c.pendingDeleteCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: WdSpace.s12),
                    child: WdInfoBanner(
                      '삭제한 기록 ${c.pendingDeleteCount}개의 서버 반영을 기다리고 있어요.',
                      tone: WdBannerTone.warning,
                    ),
                  ),
                if (c.historyNotice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: WdSpace.s12),
                    child: Column(
                      children: [
                        WdInfoBanner(
                          '서버 기록을 불러오지 못했어요. 기기에 저장된 기록은 볼 수 있어요.',
                          tone: WdBannerTone.warning,
                        ),
                        TextButton(
                          onPressed: c.loadingHistory
                              ? null
                              : () => c.loadHistory(),
                          child: const Text('다시 불러오기'),
                        ),
                      ],
                    ),
                  ),
                if (rows.isEmpty && !c.loadingHistory)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: WdSpace.s56),
                    child: Center(child: Text('아직 러닝 기록이 없어요. 첫 러닝을 시작해 보세요.')),
                  ),
                if (c.loadingHistory)
                  const Padding(
                    padding: EdgeInsets.all(WdSpace.s16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(top: WdSpace.s12),
                    child: WdSurface(
                      radius: WdRadius.r12,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(WdSpace.s16),
                        title: Text(
                          '${((row['metrics']['distanceM'] as num) / 1000).toStringAsFixed(2)} km · 자유 러닝',
                          style: WdText.ko16Bold,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: WdSpace.s8),
                          child: Text(
                            '${_date(DateTime.parse(row['startedAt'] as String).toLocal())}\n'
                            '${formatRunTime(Duration(milliseconds: (row['metrics']['elapsedMs'] as num).toInt()))} · '
                            '${formatRunPace((row['metrics']['paceSecondsPerKm'] as num?)?.toDouble())} /km\n'
                            '${_syncLabel(row['syncState'] as String)}',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.push(Routes.runRecord(row['id'] as String)),
                      ),
                    ),
                  ),
                if (c.nextCursor != null)
                  Padding(
                    padding: const EdgeInsets.only(top: WdSpace.s16),
                    child: WdButton(
                      '이전 기록 더 보기',
                      variant: WdButtonVariant.secondary,
                      onPressed: c.loadingHistory
                          ? null
                          : () => c.loadHistory(more: true),
                    ),
                  ),
                if (widget.myTab)
                  Padding(
                    padding: const EdgeInsets.only(top: WdSpace.s32),
                    child: WdButton(
                      '로그아웃',
                      variant: WdButtonVariant.secondary,
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).logout(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _date(DateTime t) =>
      '${t.year}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _syncLabel(String state) => switch (state) {
    'synced' => '서버 저장 완료',
    'uploading' => '기기 저장 · 전송 중',
    'processing' => '기기 저장 · 서버 처리 중',
    'blocked' => '기기 저장 · 동기화 확인 필요',
    _ => '기기 저장 · 서버 등록 대기',
  };
}

class RunRecordScreen extends ConsumerStatefulWidget {
  const RunRecordScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<RunRecordScreen> createState() => _RunRecordScreenState();
}

class _RunRecordScreenState extends ConsumerState<RunRecordScreen> {
  RunSnapshot? _remote;
  String? _remoteOwner;
  String? _error;
  bool _loading = true, _deleting = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final c = ref.read(runControllerProvider);
      await c.bindOwner();
      if (!c.records.any((r) => r.id == widget.id)) {
        final result = await c.detail(widget.id);
        if (mounted) {
          _remote = remoteRunSnapshot(result);
          _remoteOwner = c.currentOwner;
        }
      }
    } on Object {
      if (mounted) _error = '기록을 불러오지 못했어요. 다시 시도해 주세요.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    if (_deleting) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 러닝 기록을 삭제할까요?'),
        content: const Text('삭제한 기록은 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(runControllerProvider).deleteRecord(widget.id);
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('삭제하지 못했어요. 다시 시도해 주세요.')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(runControllerProvider);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final local = c.records.where((r) => r.id == widget.id).firstOrNull;
        final snapshot = local == null
            ? (_remoteOwner == c.currentOwner ? _remote : null)
            : ref.read(freeRunControllerProvider).savedSnapshot(local);
        if (snapshot != null) {
          return FreeRunResultView(
            run: snapshot,
            onConfirm: () => Navigator.pop(context),
            onDelete: _deleting ? null : _delete,
            history: true,
          );
        }
        return Scaffold(
          appBar: WdAppBar(
            title: '러닝 기록',
            onBack: () => Navigator.pop(context),
          ),
          body: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error ?? '기록을 찾을 수 없어요.'),
                      TextButton(onPressed: _load, child: const Text('다시 시도')),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
