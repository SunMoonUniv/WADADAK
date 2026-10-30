import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/features/run/application/public_ghost_candidates_controller.dart';
import 'package:wadadak/features/run/presentation/public_ghost_selection_view.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import '../fakes.dart';
import 'own_ghost_api_test.dart' show Server;

Map<String, Object?> rowJson(int i) => {
  'runRecordId': 'run-$i',
  'memberId': 'member-$i',
  'rank': i,
  'courseElapsedSeconds': 300 + i,
  'nickname': '러너$i',
  'paceSecondsPerKm': 300 + i,
  'completedAt': '2026-10-29T00:00:00Z',
};
PublicGhostCandidate row(int i) => PublicGhostCandidate.fromJson(rowJson(i));

void main() {
  test('API uses ranking prefix, exact source IDs, period/sort/cursor and account guard', () async {
    final server = Server()
      ..data = {
        'content': [rowJson(21)],
        'nextCursor': '40',
      };
    final api = RankingApiClient(
      Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    );
    final page = await api.publicGhostCandidates(
      'course-a',
      RankingPeriod.week,
      sort: PublicGhostSort.similar,
      cursor: '20',
      owner: 'me',
    );
    expect(page.entries.single.runRecordId, 'run-21');
    expect(page.nextCursor, '40');
    final request = server.requests.single;
    expect(request.path, '/api/v1/rankings/courses/course-a/ghost-candidates');
    expect(request.extra['runOwner'], 'me');
    expect(request.queryParameters, {
      'period': 'WEEK',
      'sort': 'SIMILAR',
      'cursor': '20',
    });
    server.status = 404;
    await expectLater(
      api.publicGhostCandidates('course-a', RankingPeriod.all, owner: 'me'),
      throwsA(isA<ApiException>()),
    );
  });

  test('pages beyond twenty, keeps selected source and preserves the list on append failure', () async {
    final api = FakeCourseRankingApi()
      ..publicRows[RankingPeriod.all] = [for (var i = 1; i <= 25; i++) row(i)];
    final c = PublicGhostCandidatesController(
      api,
      owner: 'me',
      courseId: 'course',
    );
    addTearDown(c.dispose);
    await c.load();
    expect(c.rows, hasLength(20));
    c.select(c.rows[10]);
    api.entriesError = const ApiException('NETWORK', '연결 실패');
    await c.load(append: true);
    expect(c.rows, hasLength(20));
    expect(c.nextCursor, '20');
    expect(c.selected!.runRecordId, 'run-11');
    api.entriesError = null;
    await c.load(append: true);
    expect(c.rows, hasLength(25));
    expect(c.nextCursor, isNull);
    c.select(c.rows.last);
    expect(c.selected!.runRecordId, 'run-25');
  });

  test(
    'filter change and disposal discard old replies and clear selected source',
    () async {
      final pending = Completer<PublicGhostPage>();
      final api = FakeCourseRankingApi()
        ..onPublicPage = (period, sort, cursor) async =>
            period == RankingPeriod.all
            ? pending.future
            : (entries: [row(22)], nextCursor: null);
      final c = PublicGhostCandidatesController(
        api,
        owner: 'me',
        courseId: 'course',
      );
      final old = c.load();
      await c.load(period: RankingPeriod.week, sort: PublicGhostSort.similar);
      c.select(c.rows.single);
      pending.complete((entries: [row(1)], nextCursor: null));
      await old;
      expect(c.selected!.runRecordId, 'run-22');
      expect(c.rows.single.runRecordId, 'run-22');
      await c.load(period: RankingPeriod.month);
      expect(c.selected, isNull);
      final late = Completer<PublicGhostPage>();
      api.onPublicPage = (_, _, _) => late.future;
      final loading = c.load();
      c.dispose();
      late.complete((entries: [row(1)], nextCursor: null));
      await loading;
      expect(c.rows, isEmpty);
    },
  );

  for (final width in [320.0, 402.0]) {
    testWidgets(
      'C10 selects exact candidate and period, loads more, fits $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 995);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = FakeCourseRankingApi()
          ..publicRows = {
            RankingPeriod.all: [row(1)],
            RankingPeriod.week: [row(12), row(13)],
          }
          ..pageSize = 1;
        final c = PublicGhostCandidatesController(
          api,
          owner: 'me',
          courseId: 'course',
        );
        addTearDown(c.dispose);
        PublicGhostChoice? choice;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [rankingApiClientProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: WdTheme.light(),
              home: PublicGhostSelectionView(
                controller: c,
                courseName: '길고 긴 코스 이름',
                onBack: () {},
                onOwn: () {},
                onSelected: (s) => choice = s,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('이번 주'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('나와 비슷한 기록'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('러너 더 보기'));
        await tester.tap(find.text('러너 더 보기'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('public-ghost-run-13')),
        );
        await tester.tap(find.byKey(const ValueKey('public-ghost-run-13')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('이 고스트와 대결하기'));
        expect(choice!.candidate.runRecordId, 'run-13');
        expect(choice!.period, RankingPeriod.week);
        expect(api.publicRequests.last.$2, PublicGhostSort.similar);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
