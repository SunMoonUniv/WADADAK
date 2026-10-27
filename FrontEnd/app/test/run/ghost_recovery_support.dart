import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/core/time/monotonic_clock.dart';
import 'package:wadadak/features/run/domain/course_run.dart';
import 'package:wadadak/features/run/domain/ghost_run.dart';
import 'package:wadadak/features/run/data/ghost_start_api.dart';

const ghostId = '019e0000-0000-7000-8000-000000000001';
const sourceId = '019e0000-0000-7000-8000-000000000002';
const courseId = '019e0000-0000-7000-8000-000000000003';
final ghostEpoch = DateTime.utc(2026, 10, 26, 1);
CourseSnapshot ghostCourse([String id = ghostId]) => CourseSnapshot(
  sessionId: id,
  courseId: courseId,
  name: '합성 코스',
  version: 0,
  route: const [GeoPoint(36, 127), GeoPoint(36.01, 127)],
  totalDistanceMeters: 1112,
);
GhostStartIntent ghostIntent({
  String owner = 'alice',
  RunClockSample clock = const RunClockSample(100000, 'boot-a'),
}) => GhostStartIntent(
  owner: owner,
  id: ghostId,
  startedAt: ghostEpoch,
  course: ghostCourse(),
  sourceId: sourceId,
  sourceSeconds: 230,
  clock: clock,
);

Map<String, dynamic> ghostApproval(GhostStartIntent intent) => {
  'version': 'GHOST_START_V1',
  'sessionId': intent.id,
  'sourceRecordId': intent.sourceId,
  'startedAt': intent.startedAt.toIso8601String(),
  'approvedAt': intent.startedAt.toIso8601String(),
  'courseValidatedAt': intent.startedAt.toIso8601String(),
  'course': intent.course.toJson(),
  'playback': {
    'version': 'GHOST_PLAYBACK_V1',
    'sourceRecordId': intent.sourceId,
    'course': {...intent.course.toJson(), 'sessionId': intent.sourceId},
    'sourcePolicyVersion': '2026-10-14',
    'sourceCalculationVersion': 'PACE_V3',
    'courseElapsedSeconds': intent.sourceSeconds,
    'durationMs': intent.sourceSeconds * 1000,
    'eligible': true,
    'unavailableReasons': <String>[],
    'quality': {
      'activeDurationMs': intent.sourceSeconds * 1000,
      'gapMs': 0,
      'maxGapMs': 0,
    },
    'samples': [
      {'elapsedMs': 0, 'coursePositionM': 0},
      {'elapsedMs': intent.sourceSeconds * 1000, 'coursePositionM': 1112},
    ],
    'spans': [
      {
        'fromMs': 0,
        'toMs': intent.sourceSeconds * 1000,
        'fromPositionM': 0,
        'toPositionM': 1112,
        'state': 'TRACKED',
      },
    ],
  },
};

class RecoveryClock {
  int ms = 100000;
  String? boot = 'boot-a';
  bool fail = false;
  Future<int> now() async => ms;
  Future<RunClockSample> sample() async {
    if (fail) throw StateError('clock unavailable');
    return RunClockSample(ms, boot);
  }
}

class RecoveryApi implements GhostStartSource {
  final posts = <GhostStartIntent>[];
  final gets = <String>[];
  Future<Map<String, dynamic>> Function(GhostStartIntent)? onStart;
  Future<Map<String, dynamic>> Function(String, String)? onGet;
  @override
  Future<Map<String, dynamic>> start(GhostStartIntent intent) async {
    posts.add(intent);
    return onStart == null ? ghostApproval(intent) : await onStart!(intent);
  }

  @override
  Future<Map<String, dynamic>> receipt(String owner, String id) async {
    gets.add('$owner/$id');
    return onGet == null
        ? ghostApproval(ghostIntent(owner: owner))
        : await onGet!(owner, id);
  }
}
