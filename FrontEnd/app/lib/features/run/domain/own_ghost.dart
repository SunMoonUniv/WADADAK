import 'dart:convert';

import 'ghost_playback.dart';

enum OwnGhostSort { best, recent }

enum OwnGhostPeriod { all, month, week }

class GhostCourseContext {
  const GhostCourseContext(this.id, this.version);
  final String id;
  final int version;
}

class OwnGhostCandidate {
  OwnGhostCandidate.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      course = GhostCourseContext(
        j['courseId'] as String,
        (j['courseVersion'] as num).toInt(),
      ),
      startedAt = DateTime.parse(j['startedAt'] as String),
      completedAt = j['completedAt'] == null
          ? null
          : DateTime.parse(j['completedAt'] as String),
      registeredAt = DateTime.parse(j['registeredAt'] as String),
      seconds = (j['courseElapsedSeconds'] as num).toInt(),
      distanceM = (j['courseDistanceMeters'] as num).toInt(),
      averageCadence = (j['averageCadence'] as num?)?.toDouble() {
    if (id.isEmpty ||
        course.id.isEmpty ||
        course.version < 0 ||
        seconds < 0 ||
        distanceM <= 0 ||
        averageCadence != null &&
            (!averageCadence!.isFinite || averageCadence! < 0)) {
      throw const FormatException('Invalid own ghost candidate');
    }
  }
  final String id;
  final GhostCourseContext course;
  final DateTime startedAt, registeredAt;
  final DateTime? completedAt;
  final int seconds, distanceM;
  final double? averageCadence;
}

class OwnGhostSummary {
  const OwnGhostSummary(this.count, this.averageSeconds, this.best);
  static const empty = OwnGhostSummary(0, null, null);
  final int count;
  final double? averageSeconds;
  final OwnGhostCandidate? best;
}

class OwnGhostPage {
  OwnGhostPage(this.content, this.nextCursor, this.summary);
  factory OwnGhostPage.fromJson(Map<String, dynamic> j) {
    final s = (j['summary'] as Map).cast<String, dynamic>();
    return OwnGhostPage(
      List.unmodifiable([
        for (final c in j['content'] as List)
          OwnGhostCandidate.fromJson((c as Map).cast<String, dynamic>()),
      ]),
      j['nextCursor'] as String?,
      OwnGhostSummary(
        (s['count'] as num).toInt(),
        (s['averageSeconds'] as num?)?.toDouble(),
        s['best'] == null
            ? null
            : OwnGhostCandidate.fromJson(
                (s['best'] as Map).cast<String, dynamic>(),
              ),
      ),
    );
  }
  final List<OwnGhostCandidate> content;
  final String? nextCursor;
  final OwnGhostSummary summary;
}

/// Keeps the full immutable response for a later screen/start adapter; no session is started here.
class OwnGhostReplay {
  OwnGhostReplay.fromJson(Map<String, dynamic> j)
    : sourceId = j['sourceRecordId'] as String,
      courseId = (j['course'] as Map?)?['courseId'] as String?,
      courseVersion = ((j['course'] as Map?)?['version'] as num?)?.toInt(),
      seconds = (j['courseElapsedSeconds'] as num).toInt(),
      playback = GhostPlayback.fromJson(j),
      payloadJson = jsonEncode(j);
  final String sourceId;
  final String? courseId;
  final int? courseVersion;
  final int seconds;
  final GhostPlayback playback;
  final String payloadJson;
}

class PreparedOwnGhost {
  const PreparedOwnGhost(this.owner, this.course, this.candidate, this.replay);
  final String owner;
  final GhostCourseContext course;
  final OwnGhostCandidate candidate;
  final OwnGhostReplay replay;
}
