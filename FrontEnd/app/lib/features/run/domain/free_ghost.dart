import 'dart:convert';

import 'course_run.dart';
import 'own_ghost.dart';

class FreeGhostCandidate {
  FreeGhostCandidate.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      startedAt = DateTime.parse(j['startedAt'] as String),
      distanceM = (j['distanceM'] as num).toDouble(),
      elapsedMs = (j['elapsedMs'] as num).toInt(),
      endReason = j['endReason'] as String,
      distanceEligible = j['distanceEligible'] == true;
  final String id, endReason;
  final DateTime startedAt;
  final double distanceM;
  final int elapsedMs;
  final bool distanceEligible;
}

class PreparedFreeGhost {
  PreparedFreeGhost(this.owner, Map<String, dynamic> j)
    : replay = OwnGhostReplay.fromJson(
        (j['playback'] as Map).cast<String, dynamic>(),
      ),
      originalDistanceM = (j['originalDistanceM'] as num).toDouble(),
      originalElapsedMs = (j['originalElapsedMs'] as num).toInt(),
      endReason = j['endReason'] as String,
      referenceHash = j['referenceHash'] as String {
    if (!replay.playback.eligible ||
        replay.playback.version != 'GHOST_PLAYBACK_FREE_V1' ||
        replay.courseId != null ||
        originalDistanceM < 1000 ||
        !originalDistanceM.isFinite ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(referenceHash) ||
        reference.route.length < 2) {
      throw const FormatException('자유 기록 고스트 준비 정보가 올바르지 않아요.');
    }
  }
  final String owner, endReason, referenceHash;
  final OwnGhostReplay replay;
  final double originalDistanceM;
  final int originalElapsedMs;
  CourseSnapshot get reference => CourseSnapshot.fromJson(
    ((jsonDecode(replay.payloadJson) as Map)['course'] as Map)
        .cast<String, dynamic>(),
  );
}
