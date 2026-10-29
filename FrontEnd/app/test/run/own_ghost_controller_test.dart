import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/features/run/application/own_ghost_controller.dart';
import 'package:wadadak/features/run/domain/own_ghost.dart';

import 'own_ghost_test_support.dart';

void main() {
  late FakeOwnGhostSource source;
  late OwnGhostController c;
  setUp(() {
    source = FakeOwnGhostSource();
    c = OwnGhostController(source, owner: 'owner-a', course: fixtureCourse());
  });
  tearDown(() => c.dispose());

  test(
    'shared candidate fixture and full summary parse without loading replay',
    () async {
      await c.load();
      expect(c.candidates.map((c) => c.id), ownGhostFixture()['recentIds']);
      expect(c.summary.count, 6);
      expect(c.summary.best!.id, (ownGhostFixture()['bestIds'] as List).first);
      expect(source.playbackRequests, isEmpty);
      expect(c.prepared, isNull);
    },
  );
  test('only selected record is loaded and validated into an immutable preparation payload', () async {
    await c.load();
    await c.select(c.candidates.first);
    expect(source.playbackRequests, [c.candidates.first.id]);
    expect(source.playbackCourses.single!.id, c.course.id);
    expect(source.playbackCourses.single!.version, c.course.version);
    expect(c.prepared!.owner, 'owner-a');
    expect(c.prepared!.replay.payloadJson, contains('GHOST_PLAYBACK_V1'));
    expect(c.prepared!.course.id, fixtureCourse().id);
  });
  test('best record outside loaded page remains selectable without replacing the chosen record', () async {
    source.page = OwnGhostPage(
      [source.page.content.first],
      null,
      source.page.summary,
    );
    await c.load();
    await c.select(c.summary.best!);
    expect(c.prepared!.candidate.id, c.summary.best!.id);
  });
  test('unavailable quality blocks preparation with the original reasons and no fallback', () async {
    await c.load();
    final chosen = c.candidates.first;
    source.onPlayback = (_, _) async => OwnGhostReplay.fromJson({
      ...replayJson(chosen),
      'eligible': false,
      'unavailableReasons': ['CONTINUOUS_GAP_EXCEEDED'],
    });
    await c.select(chosen);
    expect(c.prepared, isNull);
    expect(c.unavailableReasons, ['CONTINUOUS_GAP_EXCEEDED']);
    expect(source.playbackRequests, [chosen.id]);
  });
  for (final mismatch in [
    'source',
    'course',
    'version',
    'seconds',
    'playbackVersion',
  ]) {
    test('rejects replay $mismatch mismatch', () async {
      await c.load();
      final j = replayJson(c.candidates.first);
      switch (mismatch) {
        case 'source':
          j['sourceRecordId'] = 'different';
        case 'course':
          j['course'] = {'courseId': 'different', 'version': 3};
        case 'version':
          j['course'] = {'courseId': c.course.id, 'version': 4};
        case 'seconds':
          j['courseElapsedSeconds'] = 1;
        case 'playbackVersion':
          j['version'] = 'FUTURE';
      }
      source.onPlayback = (_, _) async => OwnGhostReplay.fromJson(j);
      await c.select(c.candidates.first);
      expect(c.prepared, isNull);
      expect(c.error, isNotNull);
    });
  }
  test('selection network error clears old ready data and retry repeats the selected request', () async {
    await c.load();
    await c.select(c.candidates.first);
    final next = c.candidates[1];
    source.onPlayback = (_, _) async =>
        throw const ApiException(ApiException.network, '연결을 확인해 주세요.');
    await c.select(next);
    expect(c.prepared, isNull);
    expect(c.error, contains('연결'));
    source.onPlayback = (_, _) async =>
        OwnGhostReplay.fromJson(replayJson(next));
    await c.retry();
    expect(c.prepared!.candidate.id, next.id);
  });
  test(
    'deleted selection is unavailable and cannot keep the previous preparation',
    () async {
      await c.load();
      await c.select(c.candidates.first);
      source.onPlayback = (_, _) async =>
          throw const ApiException('RUN-002', 'missing', status: 404);
      await c.select(c.candidates[1]);
      expect(c.prepared, isNull);
      expect(c.error, contains('사용할 수 없는'));
    },
  );
  test('later selection wins when replies arrive out of order', () async {
    await c.load();
    final first = Completer<OwnGhostReplay>();
    final a = c.candidates.first, b = c.candidates[1];
    source.onPlayback = (_, id) async =>
        id == a.id ? first.future : OwnGhostReplay.fromJson(replayJson(b));
    final pending = c.select(a);
    await c.select(b);
    first.complete(OwnGhostReplay.fromJson(replayJson(a)));
    await pending;
    expect(c.prepared!.candidate.id, b.id);
  });
  test('account change discards late selection and list responses', () async {
    await c.load();
    final choice = c.candidates.first, replay = Completer<OwnGhostReplay>();
    source.onPlayback = (_, _) => replay.future;
    final pending = c.select(choice);
    await c.changeContext(owner: 'owner-b', course: fixtureCourse());
    replay.complete(OwnGhostReplay.fromJson(replayJson(choice)));
    await pending;
    expect(c.owner, 'owner-b');
    expect(c.prepared, isNull);
    expect(source.requests.last.owner, 'owner-b');
  });
  test('context and period refresh ignore old list results and clear selection immediately', () async {
    await c.load();
    await c.select(c.candidates.first);
    final old = Completer<OwnGhostPage>();
    source.onCandidates = (_, _, _, period, _) async =>
        period == OwnGhostPeriod.month
        ? old.future
        : OwnGhostPage(const [], null, OwnGhostSummary.empty);
    final pending = c.load(period: OwnGhostPeriod.month);
    expect(c.prepared, isNull);
    final changed = c.changeContext(
      owner: 'owner-a',
      course: const GhostCourseContext('other-course', 4),
    );
    // The second request also uses MONTH; finish the shared response after invalidating both with WEEK.
    final current = c.load(period: OwnGhostPeriod.week);
    old.complete(source.page);
    await Future.wait([pending, changed, current]);
    expect(c.candidates, isEmpty);
    expect(c.summary.count, 0);
    expect(c.error, isNull);
  });
  test(
    'pagination failure keeps rows and cursor and retries the same page',
    () async {
      final whole = source.page;
      source.page = OwnGhostPage(
        [whole.content.first],
        'page-2',
        whole.summary,
      );
      await c.load();
      source.onCandidates = (_, _, _, _, cursor) async =>
          throw const ApiException(ApiException.network, 'offline');
      await c.loadMore();
      expect(c.candidates, hasLength(1));
      expect(c.nextCursor, 'page-2');
      source.onCandidates = (_, _, _, _, cursor) async =>
          OwnGhostPage(whole.content.sublist(1), null, whole.summary);
      await c.retry();
      expect(c.candidates, hasLength(6));
      expect(c.nextCursor, isNull);
      expect(source.requests.last.cursor, 'page-2');
    },
  );
  test('canceling selection drops a late response', () async {
    await c.load();
    final reply = Completer<OwnGhostReplay>(), chosen = c.candidates.first;
    source.onPlayback = (_, _) => reply.future;
    final pending = c.select(chosen);
    c.clearSelection();
    reply.complete(OwnGhostReplay.fromJson(replayJson(chosen)));
    await pending;
    expect(c.prepared, isNull);
    expect(c.selectingId, isNull);
  });
  test(
    'foreign candidate page is rejected instead of exposing another course',
    () async {
      source.page = OwnGhostPage(
        [
          OwnGhostCandidate.fromJson({
            ...(ownGhostFixture()['records'] as List).first
                as Map<String, dynamic>,
            'courseId': 'other-course',
          }),
        ],
        null,
        OwnGhostSummary.empty,
      );
      await c.load();
      expect(c.candidates, isEmpty);
      expect(c.error, isNotNull);
    },
  );
  test(
    'a record not returned by the candidate endpoint cannot be selected',
    () async {
      await c.load();
      final external = OwnGhostCandidate.fromJson(
        (ownGhostFixture()['records'] as List).first as Map<String, dynamic>,
      );
      await expectLater(c.select(external), throwsArgumentError);
      expect(source.playbackRequests, isEmpty);
    },
  );
}
