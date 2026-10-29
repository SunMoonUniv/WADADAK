import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../run/application/run_controller.dart';
import 'run_history_rows.dart';

/// 내 러닝 기록을 끝까지 받는 화면(I1 내 러닝 기록 · E3 마이페이지)이 함께 쓴다.
///
/// run은 기록을 하나씩만 주고 합계는 받는 쪽(앱)이 낸다(팀 결정). 그래서 화면이 열리면 첫 페이지를 받고,
/// 한 페이지를 받을 때마다 다음 페이지를 이어 받는다. 실패하면 멈추고 화면이 다시 받게 한다.
/// 기록 데이터(기기 · 서버 · 동기화 · 삭제)는 달리기 담당의 `runController`를 그대로 쓴다.
mixin AllRunHistory<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// 한 번에 받는 기록 수(서버 최대). 끝까지 받으므로 클수록 요청이 적다.
  static const pageSize = 50;

  late final RunController runs;

  /// 첫 페이지를 받기 전이다. 이때는 받을 페이지가 남았는지도 모른다.
  var _started = false;

  @override
  void initState() {
    super.initState();
    runs = ref.read(runControllerProvider)..addListener(_loadRest);
    Future.microtask(() async {
      await runs.bindOwner();
      if (!mounted) return;
      await runs.loadHistory(pageSize: pageSize);
      if (!mounted) return;
      setState(() => _started = true);
      _loadRest();
    });
  }

  @override
  void dispose() {
    runs.removeListener(_loadRest);
    super.dispose();
  }

  void _loadRest() {
    if (!mounted || runs.loadingHistory || runs.nextCursor == null || runs.historyNotice != null) return;
    unawaited(runs.loadHistory(more: true, pageSize: pageSize));
  }

  /// 기기 기록과 서버 기록을 합친 내 기록 전부(최근 순).
  List<RunHistoryRow> get allRuns =>
      runHistoryRows(local: runs.records, remote: runs.remoteRecords, deletedIds: runs.deletedIds);

  /// 아직 끝까지 받지 못했다. 이때 합계는 덜 나오므로 화면은 로딩으로 보인다.
  bool get loadingAllRuns =>
      runs.historyNotice == null && (!_started || runs.nextCursor != null || runs.loadingHistory);
}
