import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/features/run/application/run_controller.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/domain/recording_models.dart' as recording;
import 'package:wadadak/features/run/domain/run_voice.dart';

import '../../run/recording/run_controller_test.dart' as fake;

/// 서버 기록 한 줄(RecordSummary). [course]면 코스를 달린 기록, [ghost]가 있으면 고스트 대결이다.
/// [gpsGap]은 서버의 GPS 끊김 판정이다(null이면 아직 판정 전). [route]는 썸네일 경로이고, 없으면 그 경로가 생기기 전 예전 기록이다.
Map<String, dynamic> recordSummary(
  String id,
  String startedAt, {
  double meters = 5000,
  int seconds = 1800,
  bool? gpsGap = true,
  bool course = false,
  String? ghost,
  List<List<GeoPoint>>? route,
}) => {
  'id': id,
  'startedAt': startedAt,
  'endReason': 'USER',
  'metrics': {
    'distanceM': meters,
    'elapsedMs': seconds * 1000,
    'activeMs': seconds * 1000,
    'movingMs': seconds * 1000,
    'paceSecondsPerKm': seconds / meters * 1000,
    'gapCount': 0,
  },
  'course': course
      ? {
          'courseId': 'course-1',
          'courseName': '한강 야경 5K',
          'completed': true,
          'progressPercent': 100.0,
          'reviewEligible': true,
        }
      : null,
  'gpsGap': gpsGap == null ? null : {'passed': gpsGap, 'version': 'v1'},
  'ghost': ghost == null ? null : {'outcome': ghost, 'reason': 'COMPLETED_TIME_COMPARISON', 'completed': true},
  if (route != null)
    'routeThumbnail': {
      'version': 'RUN_ROUTE_THUMBNAIL_V1',
      'segments': [
        for (final segment in route) [for (final point in segment) point.toJson()],
      ],
    },
};

/// 서버 기록. [pages]를 차례로 준다(다음 페이지 커서는 `page-<번호>`). [fail]이면 받지 못한다.
class RecordHistoryApi extends fake.TestApi {
  RecordHistoryApi([this.pages = const [[]]]);

  List<List<Map<String, dynamic>>> pages;
  bool fail = false;
  final cursors = <String?>[];
  final sizes = <int?>[];

  @override
  Future<Map<String, dynamic>> history(String owner, {String? cursor, int? size}) async {
    cursors.add(cursor);
    sizes.add(size);
    if (fail) throw StateError('offline');
    final index = cursor == null ? 0 : int.parse(cursor.substring('page-'.length));
    return {'content': pages[index], 'nextCursor': index + 1 < pages.length ? 'page-${index + 1}' : null};
  }
}

/// 기기 저장소. 실제 DB를 열지 않도록 목록 · 삭제 · 고스트 · 음성 설정을 메모리로 바꾼다(I1 테스트와 같다).
class MemoryRunStore extends fake.FailingStore {
  /// 기기 기록. 올리지 않은 기록은 `syncState: 'pending'`이다.
  List<recording.LocalRun> local = [];

  @override
  Future<Set<String>> deletedIds(String owner) async => {};

  @override
  Future<List<String>> pendingDeletions(String owner) async => [];

  @override
  Future<List<PendingGhostStart>> pendingGhostStarts(String owner) async => [];

  @override
  Future<List<CourseStartIntent>> pendingCourseStarts(String owner) async => [];

  @override
  Future<List<String>> pendingGhostClosures(String owner) async => [];

  @override
  Future<RunVoiceSettings> voiceSettings(String owner) async => const RunVoiceSettings();

  @override
  Future<List<recording.LocalRun>> list(
    String owner, {
    bool summaryOnly = false,
    bool pendingOnly = false,
    bool unfinishedOnly = false,
    String? id,
  }) async => unfinishedOnly || pendingOnly ? [] : local;
}

/// `alice`로 로그인한 달리기 컨트롤러. 기기(GPS · DB) 없이 돈다. 테스트가 끝나면 dispose한다.
RunController recordRuns(MemoryRunStore store, RecordHistoryApi history) {
  final gps = fake.TestLocation();
  return RunController(store, gps, history, () async => 'alice', automaticTicks: false, nowMs: gps.nowMs);
}
