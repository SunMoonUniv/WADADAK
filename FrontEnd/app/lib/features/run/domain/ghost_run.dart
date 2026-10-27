import 'dart:convert';

import '../../../core/time/monotonic_clock.dart';
import 'course_run.dart';
import 'own_ghost.dart';

/// Durable request identity, written before the first network request.
class GhostStartIntent {
  GhostStartIntent({
    required this.owner,
    required this.id,
    required this.startedAt,
    required this.course,
    required this.sourceId,
    required this.sourceSeconds,
    required this.clock,
    this.referenceHash,
    this.publicPeriod,
  }) {
    if (owner.isEmpty ||
        id.isEmpty ||
        id == sourceId ||
        sourceId.isEmpty ||
        course.sessionId != id ||
        (course.courseId == null &&
            (referenceHash == null ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(referenceHash!))) ||
        course.version == null ||
        course.version! < 0 ||
        course.route.length < 2 ||
        sourceSeconds < 0 ||
        clock.elapsedMs < 0 ||
        (publicPeriod != null &&
            (course.courseId == null ||
                !['ALL', 'MONTH', 'WEEK'].contains(publicPeriod)))) {
      throw const FormatException('고스트 시작 정보가 일치하지 않아요.');
    }
  }
  final String owner, id, sourceId;
  final String? referenceHash;
  final String? publicPeriod;
  bool get isFree => course.courseId == null;
  String get playbackVersion =>
      isFree ? 'GHOST_PLAYBACK_FREE_V1' : 'GHOST_PLAYBACK_V1';
  final int sourceSeconds;
  final DateTime startedAt;
  final CourseSnapshot course;
  final RunClockSample clock;
  Map<String, dynamic> get request => {
    'courseId': course.courseId,
    'courseVersion': course.version,
    'sourceRecordId': sourceId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'playbackVersion': playbackVersion,
    'referenceHash': ?referenceHash,
    'publicPeriod': ?publicPeriod,
  };
  Map<String, dynamic> toJson() => {
    'version': 'GHOST_DEVICE_V1',
    'owner': owner,
    'id': id,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'course': course.toJson(),
    'sourceId': sourceId,
    'sourceSeconds': sourceSeconds,
    'referenceHash': ?referenceHash,
    'publicPeriod': ?publicPeriod,
    'clock': clock.toJson(),
  };
  factory GhostStartIntent.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 'GHOST_DEVICE_V1') {
      throw const FormatException('Unknown ghost storage version');
    }
    return GhostStartIntent(
      owner: j['owner'] as String,
      id: j['id'] as String,
      startedAt: DateTime.parse(j['startedAt'] as String),
      course: CourseSnapshot.fromJson(
        (j['course'] as Map).cast<String, dynamic>(),
      ),
      sourceId: j['sourceId'] as String,
      sourceSeconds: j['sourceSeconds'] as int,
      referenceHash: j['referenceHash'] as String?,
      publicPeriod: j['publicPeriod'] as String?,
      clock: RunClockSample.fromJson(
        (j['clock'] as Map).cast<String, dynamic>(),
      ),
    );
  }
}

/// Immutable copy of the server receipt, validated against the persisted request.
class GhostRunContext {
  GhostRunContext(this.intent, Map<String, dynamic> approval)
    : approvalJson = jsonEncode(approval) {
    final c = CourseSnapshot.fromJson(
      (approval['course'] as Map).cast<String, dynamic>(),
    );
    final replay = OwnGhostReplay.fromJson(
      (approval['playback'] as Map).cast<String, dynamic>(),
    );
    if (approval['version'] !=
            (intent.isFree ? 'GHOST_START_FREE_V1' : 'GHOST_START_V1') ||
        approval['publicPeriod'] != intent.publicPeriod ||
        approval['sessionId'] != intent.id ||
        approval['sourceRecordId'] != intent.sourceId ||
        DateTime.parse(approval['startedAt'] as String) != intent.startedAt ||
        c.sessionId != intent.id ||
        c.courseId != intent.course.courseId ||
        c.version != intent.course.version ||
        c.totalDistanceMeters != intent.course.totalDistanceMeters ||
        !sameRoute(c, intent.course) ||
        replay.sourceId != intent.sourceId ||
        replay.courseId != c.courseId ||
        replay.courseVersion != c.version ||
        replay.seconds != intent.sourceSeconds ||
        !replay.playback.eligible ||
        replay.playback.version != intent.playbackVersion) {
      throw const FormatException('서버의 고스트 시작 확인이 선택한 대결과 달라요.');
    }
    DateTime.parse(approval['approvedAt'] as String);
    DateTime.parse(approval['courseValidatedAt'] as String);
  }
  final GhostStartIntent intent;
  final String approvalJson;
  Map<String, dynamic> get approval =>
      (jsonDecode(approvalJson) as Map).cast<String, dynamic>();
  OwnGhostReplay get replay => OwnGhostReplay.fromJson(
    (approval['playback'] as Map).cast<String, dynamic>(),
  );
  Map<String, dynamic> toJson() => {
    'intent': intent.toJson(),
    'approval': approval,
  };
  factory GhostRunContext.fromJson(Map<String, dynamic> j) => GhostRunContext(
    GhostStartIntent.fromJson((j['intent'] as Map).cast<String, dynamic>()),
    (j['approval'] as Map).cast<String, dynamic>(),
  );
  static bool sameRoute(CourseSnapshot a, CourseSnapshot b) {
    if (a.breaks.join(',') != b.breaks.join(',')) return false;
    if (a.route.length != b.route.length) return false;
    for (var i = 0; i < a.route.length; i++) {
      if (a.route[i].lat != b.route[i].lat ||
          a.route[i].lng != b.route[i].lng) {
        return false;
      }
    }
    return true;
  }
}

class PendingGhostStart {
  const PendingGhostStart(this.intent, this.context, this.checkpointClock);
  final GhostStartIntent intent;
  final GhostRunContext? context;
  final RunClockSample checkpointClock;
}
