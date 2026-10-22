import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../run/application/free_run_controller.dart';
import '../run/application/run_controller.dart';
import '../run/application/run_result_mapper.dart';
import '../run/domain/run_models.dart';
import '../run/presentation/free_run_result_view.dart';

/// I1에서 고른 기록 하나. 달리기 결과 화면(D1)을 기록 보기 모드로 띄운다.
///
/// 기기에 남은 기록이면 기기 것을, 아니면 서버 상세를 받아 보인다. 삭제하면 목록으로 돌아간다.
/// (달리기 담당이 #100에서 지운 기록 상세를 MY로 옮겼다. 화면 · 데이터는 달리기 쪽 것을 그대로 쓴다)
class MyRunRecordScreen extends ConsumerStatefulWidget {
  const MyRunRecordScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<MyRunRecordScreen> createState() => _MyRunRecordScreenState();
}

class _MyRunRecordScreenState extends ConsumerState<MyRunRecordScreen> {
  RunSnapshot? _remote;
  String? _remoteOwner, _loadedState, _error;
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
      final owner = c.currentOwner;
      _loadedState = c.records.where((r) => r.id == widget.id).firstOrNull?.syncState;
      final local = await c.localRecord(widget.id);
      if (c.currentOwner != owner) return;
      if (local != null) {
        if (mounted) {
          _remote = ref.read(freeRunControllerProvider).savedSnapshot(local);
          _remoteOwner = owner;
          _loadedState = local.syncState;
        }
      } else {
        final result = await c.detail(widget.id);
        if (mounted && c.currentOwner == owner) {
          _remote = remoteRunSnapshot(result);
          _remoteOwner = owner;
        }
      }
    } on Object {
      if (mounted) _error = '기록을 불러오지 못했어요. 다시 시도해 주세요.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 러닝 기록을 삭제할까요?'),
        content: const Text('삭제한 기록은 되돌릴 수 없어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제하지 못했어요. 다시 시도해 주세요.')));
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
        // 보는 동안 동기화 상태가 바뀌면(업로드 끝 등) 다시 받는다
        if (local != null && !local.inputsLoaded && _loadedState != local.syncState && !_loading) {
          _loading = true;
          Future.microtask(_load);
        }
        final snapshot = c.deletedIds.contains(widget.id)
            ? null
            : local != null && local.inputsLoaded
            ? ref.read(freeRunControllerProvider).savedSnapshot(local)
            : (_remoteOwner == c.currentOwner ? _remote : null);
        if (snapshot != null) {
          return FreeRunResultView(
            run: snapshot,
            onConfirm: () => Navigator.pop(context),
            onDelete: _deleting ? null : _delete,
            history: true,
          );
        }
        return Scaffold(
          appBar: WdAppBar(title: '러닝 기록', onBack: () => Navigator.pop(context)),
          body: Center(
            child: _loading
                ? const CircularProgressIndicator(color: WdColors.ink)
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
