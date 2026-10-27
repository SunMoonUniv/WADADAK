import 'dart:convert';

import 'course_run.dart';
import 'own_ghost.dart';

class PreparedPublicGhost implements PreparedCourseGhost {
  PreparedPublicGhost(this.owner, Map<String, dynamic> json)
    : publicPeriod = json['publicPeriod'] as String,
      rank = (json['candidate']['rank'] as num).toInt(),
      sourceId = json['candidate']['runRecordId'] as String,
      replay = OwnGhostReplay.fromJson(
        (json['playback'] as Map).cast<String, dynamic>(),
      ) {
    if (!['ALL', 'MONTH', 'WEEK'].contains(publicPeriod) ||
        rank < 1 ||
        sourceId != replay.sourceId ||
        replay.playback.version != 'GHOST_PLAYBACK_V1' ||
        !replay.playback.eligible ||
        replay.courseId == null ||
        replay.courseVersion == null ||
        replay.seconds != json['candidate']['courseElapsedSeconds']) {
      throw const FormatException('사용할 수 없는 공개 고스트입니다.');
    }
  }
  @override
  final String owner, sourceId, publicPeriod;
  final int rank;
  @override
  final OwnGhostReplay replay;
  @override
  int get seconds => replay.seconds;
  @override
  GhostCourseContext get course =>
      GhostCourseContext(replay.courseId!, replay.courseVersion!);
  late final CourseSnapshot reference = CourseSnapshot.fromJson(
    ((jsonDecode(replay.payloadJson) as Map)['course'] as Map)
        .cast<String, dynamic>(),
  );
}
