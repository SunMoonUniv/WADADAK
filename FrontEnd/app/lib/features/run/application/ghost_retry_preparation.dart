import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/api/run_api_client.dart';
import '../data/free_ghost_api.dart';
import '../data/own_ghost_api.dart';
import '../data/public_ghost_api.dart';
import '../domain/course_run.dart';
import '../domain/free_ghost.dart';
import '../domain/ghost_comparison.dart';
import '../domain/own_ghost.dart';
import '../domain/public_ghost.dart';

/// Preparation only: revalidate this exact source/period; never starts measurement.
class GhostRetryPreparation {
  GhostRetryPreparation(this.api);
  final RunApiClient api;
  Future<({PreparedFreeGhost? free, PreparedCourseGhost? course})> prepare(
    String owner,
    GhostComparison detail,
  ) => _prepare(owner, detail).timeout(const Duration(seconds: 15));
  Future<({PreparedFreeGhost? free, PreparedCourseGhost? course})> _prepare(
    String owner,
    GhostComparison d,
  ) async {
    if (!d.available) throw StateError('대결 준비 정보를 확인할 수 없어요.');
    if (d.kind == 'OWN_FREE') {
      final p = PreparedFreeGhost(
        owner,
        await FreeGhostApi(api).prepare(owner, d.sourceId),
      );
      if (p.replay.sourceId != d.sourceId ||
          p.reference.totalDistanceMeters != d.distanceM) {
        throw const FormatException('다시 도전할 기준 경로가 달라졌어요.');
      }
      return (free: p, course: null);
    }
    if (d.kind == 'PUBLIC_COURSE') {
      final p = PreparedPublicGhost(
        owner,
        await PublicGhostApi(api)
            .prepare(owner, d.sourceId, d.courseId!, d.publicPeriod!),
      );
      if (p.sourceId != d.sourceId ||
          p.course.id != d.courseId ||
          p.publicPeriod != d.publicPeriod ||
          p.reference.totalDistanceMeters != d.distanceM) {
        throw const FormatException('다시 도전할 고스트가 달라졌어요.');
      }
      return (free: null, course: p);
    }
    if (d.kind != 'OWN_COURSE' || d.courseId == null) {
      throw StateError('대결 준비 정보를 확인할 수 없어요.');
    }
    final id = const Uuid().v7();
    final current = CourseSnapshot.fromJson(
      await api.prepareCourse(owner, id, d.courseId!),
    );
    if (current.sessionId != id ||
        current.courseId != d.courseId ||
        current.version == null ||
        current.totalDistanceMeters != d.distanceM ||
        current.route.length < 2) {
      throw const FormatException('코스가 바뀌었어요.');
    }
    final course = GhostCourseContext(current.courseId!, current.version!);
    final replay = await OwnGhostApi(api)
        .playback(owner, d.sourceId, course: course);
    final reference = CourseSnapshot.fromJson(
      ((jsonDecode(replay.payloadJson) as Map)['course'] as Map)
          .cast<String, dynamic>(),
    );
    if (replay.sourceId != d.sourceId ||
        !replay.playback.eligible ||
        replay.playback.version != 'GHOST_PLAYBACK_V1' ||
        replay.courseId != course.id ||
        replay.courseVersion != course.version ||
        reference.totalDistanceMeters != current.totalDistanceMeters ||
        reference.route.length != current.route.length ||
        reference.breaks.join(',') != current.breaks.join(',')) {
      throw const FormatException('같은 경로의 고스트를 확인하지 못했어요.');
    }
    for (var i = 0; i < reference.route.length; i++) {
      if (reference.route[i].lat != current.route[i].lat ||
          reference.route[i].lng != current.route[i].lng) {
        throw const FormatException('코스 경로가 바뀌었어요.');
      }
    }
    return (free: null, course: _PreparedRetryGhost(owner, course, replay));
  }
}

class _PreparedRetryGhost implements PreparedCourseGhost {
  const _PreparedRetryGhost(this.owner, this.course, this.replay);
  @override
  final String owner;
  @override
  final GhostCourseContext course;
  @override
  final OwnGhostReplay replay;
  @override
  String get sourceId => replay.sourceId;
  @override
  int get seconds => replay.seconds;
  @override
  String? get publicPeriod => null;
}
