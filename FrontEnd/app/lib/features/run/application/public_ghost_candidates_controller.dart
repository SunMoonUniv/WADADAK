import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/ranking_api_client.dart';

typedef PublicGhostChoice = ({GhostCandidate candidate, RankingPeriod period});

/// One course/account per instance. Discard responses after filter changes or disposal.
class PublicGhostCandidatesController extends ChangeNotifier {
  PublicGhostCandidatesController(
    this.api, {
    required this.owner,
    required this.courseId,
  });
  final RankingApiClient api;
  final String owner, courseId;
  RankingPeriod period = RankingPeriod.all;
  PublicGhostSort sort = PublicGhostSort.fastest;
  List<PublicGhostCandidate> rows = const [];
  String? nextCursor, error, selectedId;
  bool loading = false, loadingMore = false, disposed = false;
  int epoch = 0;

  PublicGhostCandidate? get selected =>
      rows.where((r) => r.runRecordId == selectedId).firstOrNull;
  void clearSelection() {
    selectedId = null;
    if (!disposed) notifyListeners();
  }

  void select(PublicGhostCandidate row) {
    if (disposed || loading || !rows.contains(row)) return;
    selectedId = row.runRecordId;
    notifyListeners();
  }

  Future<void> load({
    RankingPeriod? period,
    PublicGhostSort? sort,
    bool append = false,
  }) async {
    if (disposed || append && (loading || loadingMore || nextCursor == null)) {
      return;
    }
    this.period = period ?? this.period;
    this.sort = sort ?? this.sort;
    final token = ++epoch, cursor = append ? nextCursor : null;
    error = null;
    if (append) {
      loadingMore = true;
    } else {
      rows = const [];
      nextCursor = null;
      selectedId = null;
      loading = true;
      loadingMore = false;
    }
    notifyListeners();
    try {
      final page = await api.publicGhostCandidates(
        courseId,
        this.period,
        sort: this.sort,
        cursor: cursor,
        owner: owner,
      );
      if (disposed || token != epoch) return;
      if (page.entries.any((r) => r.memberId == owner) ||
          page.nextCursor != null && page.nextCursor == cursor) {
        throw const FormatException('Invalid public candidate page');
      }
      final ids = rows.map((r) => r.runRecordId).toSet();
      rows = [...rows, ...page.entries.where((r) => ids.add(r.runRecordId))];
      nextCursor = page.nextCursor;
    } catch (e) {
      if (!disposed && token == epoch) {
        error = e is ApiException ? e.message : '공개 기록을 불러오지 못했어요. 다시 시도해 주세요.';
      }
    } finally {
      if (!disposed && token == epoch) {
        loading = false;
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    epoch++;
    super.dispose();
  }
}
