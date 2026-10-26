import 'dart:convert';
import 'dart:io';

import 'package:wadadak/features/run/data/own_ghost_api.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';

Map<String, dynamic> ownGhostFixture() => (jsonDecode(
  File('../../run/fixtures/own_ghost_candidates_v1.json').readAsStringSync(),
) as Map).cast<String, dynamic>();

OwnGhostPage fixturePage() => OwnGhostPage.fromJson(
  (ownGhostFixture()['page'] as Map).cast<String, dynamic>(),
);

GhostCourseContext fixtureCourse() {
  final c = ownGhostFixture()['course'] as Map;
  return GhostCourseContext(c['courseId'] as String, c['version'] as int);
}

Map<String, dynamic> replayJson(OwnGhostCandidate c) => {
  'version': 'GHOST_PLAYBACK_V1',
  'sourceRecordId': c.id,
  'course': {'courseId': c.course.id, 'version': c.course.version},
  'courseElapsedSeconds': c.seconds,
  'durationMs': c.seconds * 1000,
  'eligible': true,
  'unavailableReasons': <String>[],
  'samples': [
    {'elapsedMs': 0, 'coursePositionM': 0},
    {'elapsedMs': c.seconds * 1000, 'coursePositionM': c.distanceM},
  ],
  'spans': [
    {
      'fromMs': 0,
      'toMs': c.seconds * 1000,
      'fromPositionM': 0,
      'toPositionM': c.distanceM,
      'state': 'TRACKED',
    },
  ],
};

class FakeOwnGhostSource implements OwnGhostSource {
  OwnGhostPage page = fixturePage();
  Future<OwnGhostPage> Function(
    String owner,
    GhostCourseContext course,
    OwnGhostSort sort,
    OwnGhostPeriod period,
    String? cursor,
  )?
  onCandidates;
  Future<OwnGhostReplay> Function(String owner, String id)? onPlayback;
  final requests =
      <
        ({
          String owner,
          String course,
          OwnGhostSort sort,
          OwnGhostPeriod period,
          String? cursor,
        })
      >[];
  final playbackRequests = <String>[];

  @override
  Future<OwnGhostPage> candidates(
    String owner,
    GhostCourseContext course, {
    required OwnGhostSort sort,
    required OwnGhostPeriod period,
    String? cursor,
  }) async {
    requests.add((
      owner: owner,
      course: course.id,
      sort: sort,
      period: period,
      cursor: cursor,
    ));
    return onCandidates == null
        ? page
        : onCandidates!(owner, course, sort, period, cursor);
  }

  @override
  Future<OwnGhostReplay> playback(String owner, String recordId) async {
    playbackRequests.add(recordId);
    if (onPlayback != null) return onPlayback!(owner, recordId);
    final c = [
      ...page.content,
      if (page.summary.best != null) page.summary.best!,
    ].firstWhere((c) => c.id == recordId);
    return OwnGhostReplay.fromJson(replayJson(c));
  }
}
