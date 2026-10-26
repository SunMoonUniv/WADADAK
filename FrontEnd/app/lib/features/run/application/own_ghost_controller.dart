import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../data/own_ghost_api.dart';
import '../domain/ghost_playback.dart';
import '../domain/own_ghost.dart';

/// Selection preparation only. Never calls the F6 recorder, start signal, map or MY.
class OwnGhostController extends ChangeNotifier {
  factory OwnGhostController(
    OwnGhostSource source, {
    required String owner,
    required GhostCourseContext course,
  }) => OwnGhostController._(source, owner, course);
  OwnGhostController._(this.source, this._owner, this._course);
  final OwnGhostSource source;
  String _owner;
  GhostCourseContext _course;
  String get owner => _owner;
  GhostCourseContext get course => _course;
  OwnGhostSort sort = OwnGhostSort.recent;
  OwnGhostPeriod period = OwnGhostPeriod.all;
  List<OwnGhostCandidate> candidates = const [];
  OwnGhostSummary summary = OwnGhostSummary.empty;
  String? nextCursor, selectingId, error;
  List<String> unavailableReasons = const [];
  PreparedOwnGhost? prepared;
  bool loading = false, loadingMore = false;
  bool _disposed = false;
  int _listEpoch = 0, _selectEpoch = 0;
  Future<void> Function()? _retry;
  Future<void> retry() => _retry?.call() ?? Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _belongs(OwnGhostCandidate c) =>
      c.course.id == course.id && c.course.version == course.version;
  void _checkPage(OwnGhostPage page) {
    if (page.content.any((c) => !_belongs(c)) ||
        page.summary.best != null && !_belongs(page.summary.best!) ||
        page.summary.count < 0 ||
        page.summary.averageSeconds != null &&
            (!page.summary.averageSeconds!.isFinite ||
                page.summary.averageSeconds! < 0)) {
      throw const FormatException('Candidate context mismatch');
    }
  }

  Future<void> load({OwnGhostSort? sort, OwnGhostPeriod? period}) async {
    if (_disposed) return;
    this.sort = sort ?? this.sort;
    this.period = period ?? this.period;
    final epoch = ++_listEpoch;
    _selectEpoch++;
    candidates = const [];
    summary = OwnGhostSummary.empty;
    nextCursor = null;
    prepared = null;
    selectingId = null;
    error = null;
    unavailableReasons = const [];
    loading = true;
    loadingMore = false;
    _retry = null;
    _notify();
    try {
      final page = await source.candidates(
        owner,
        course,
        sort: this.sort,
        period: this.period,
      );
      if (_disposed || epoch != _listEpoch) return;
      _checkPage(page);
      candidates = List.unmodifiable(page.content);
      summary = page.summary;
      nextCursor = page.nextCursor;
    } catch (e) {
      if (_disposed || epoch != _listEpoch) return;
      error = _message(e);
      _retry = () => load();
    } finally {
      if (!_disposed && epoch == _listEpoch) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = nextCursor, epoch = _listEpoch;
    if (_disposed || loading || loadingMore || cursor == null) return;
    loadingMore = true;
    error = null;
    _retry = null;
    _notify();
    try {
      final page = await source.candidates(
        owner,
        course,
        sort: sort,
        period: period,
        cursor: cursor,
      );
      if (_disposed || epoch != _listEpoch) return;
      _checkPage(page);
      if (page.nextCursor == cursor) {
        throw const FormatException('Repeated cursor');
      }
      final seen = candidates.map((c) => c.id).toSet();
      candidates = List.unmodifiable([
        ...candidates,
        ...page.content.where((c) => seen.add(c.id)),
      ]);
      summary = page.summary;
      nextCursor = page.nextCursor;
    } catch (e) {
      if (_disposed || epoch != _listEpoch) return;
      error = _message(e);
      _retry = loadMore;
    } finally {
      if (!_disposed && epoch == _listEpoch) {
        loadingMore = false;
        _notify();
      }
    }
  }

  Future<void> select(OwnGhostCandidate candidate) async {
    if (_disposed || loading) return;
    if (!_belongs(candidate) ||
        !candidates.any((c) => identical(c, candidate)) &&
            !identical(summary.best, candidate)) {
      throw ArgumentError('Select a loaded candidate');
    }
    final epoch = ++_selectEpoch;
    selectingId = candidate.id;
    prepared = null;
    error = null;
    unavailableReasons = const [];
    _retry = null;
    _notify();
    try {
      final replay = await source.playback(owner, candidate.id);
      if (_disposed || epoch != _selectEpoch) return;
      if (!replay.playback.eligible) {
        unavailableReasons = replay.playback.reasons.isEmpty
            ? const ['UNAVAILABLE']
            : replay.playback.reasons;
        return;
      }
      if (replay.sourceId != candidate.id ||
          replay.courseId != course.id ||
          replay.courseVersion != course.version ||
          replay.seconds != candidate.seconds ||
          replay.playback.at(0).state == GhostPlaybackState.unavailable) {
        throw const FormatException('Selected replay context mismatch');
      }
      prepared = PreparedOwnGhost(owner, course, candidate, replay);
    } catch (e) {
      if (_disposed || epoch != _selectEpoch) return;
      error = _message(e);
      _retry = () => select(candidate);
    } finally {
      if (!_disposed && epoch == _selectEpoch) {
        selectingId = null;
        _notify();
      }
    }
  }

  void clearSelection() {
    _selectEpoch++;
    prepared = null;
    selectingId = null;
    error = null;
    unavailableReasons = const [];
    _retry = null;
    _notify();
  }

  Future<void> changeContext({
    required String owner,
    required GhostCourseContext course,
  }) {
    _owner = owner;
    _course = course;
    return load();
  }

  static String _message(Object e) => e is ApiException
      ? (e.status == 404 ? '사용할 수 없는 고스트입니다. 다른 기록을 선택해 주세요.' : e.message)
      : '기록을 확인하지 못했어요. 다시 시도해 주세요.';

  @override
  void dispose() {
    _disposed = true;
    _listEpoch++;
    _selectEpoch++;
    super.dispose();
  }
}
