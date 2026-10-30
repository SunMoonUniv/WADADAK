import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/run_api_client.dart';
import 'package:wadadak/features/run/application/ghost_retry_preparation.dart';
import 'package:wadadak/features/run/data/ghost_comparison_api.dart';
import 'package:wadadak/features/run/domain/ghost_comparison.dart';
import 'package:wadadak/features/run/domain/run_models.dart';
import 'package:wadadak/features/run/presentation/ghost_result_screen.dart';
import 'package:wadadak_design_system/wadadak_design_system.dart';

import 'ghost_recovery_support.dart';
import 'free_ghost_flow_test.dart' show preparation;

Map<String, dynamic> comparisonJson({
  bool completed = true,
  String kind = 'OWN_COURSE',
  String outcome = 'WIN',
}) => {
  'version': 'GHOST_COMPARISON_V1',
  'sessionId': ghostId,
  'sourceRecordId': sourceId,
  'result': {
    'sessionId': ghostId,
    'sourceRecordId': sourceId,
    'outcome': outcome,
    'completed': completed,
    'courseElapsedSeconds': completed ? 200 : 300,
    'sourceElapsedSeconds': 230,
    'reason': completed
        ? 'COMPLETED_TIME_COMPARISON'
        : 'VOLUNTARY_AFTER_GHOST_FINISH',
  },
  'status': 'AVAILABLE',
  'courseId': kind == 'OWN_FREE' ? null : courseId,
  'courseName': '한강 야경 5K',
  'distanceMeters': 5200,
  'sourceKind': kind,
  'publicPeriod': kind == 'PUBLIC_COURSE' ? 'WEEK' : null,
  'sourceState': 'AVAILABLE',
  'reachedMeters': completed ? 5200 : 400,
  'personalBest': kind == 'OWN_FREE' ? 'NOT_APPLICABLE' : 'UNCHANGED',
  'previousBestSeconds': 190,
  'ours': {
    'elapsedSeconds': completed ? 200 : null,
    'activeMs': 195000,
    'paceSecondsPerKm': completed ? 38.46 : null,
    'averageCadence': 174,
    'bestSegment': completed ? 4 : null,
  },
  'ghost': {
    'elapsedSeconds': 230,
    'activeMs': kind == 'PUBLIC_COURSE' ? null : 220000,
    'paceSecondsPerKm': 44.23,
    'averageCadence': kind == 'PUBLIC_COURSE' ? null : 170,
    'bestSegment': 1,
  },
  'segments': [
    for (var i = 0; i < 6; i++)
      {
        'number': i + 1,
        'fromMeters': i * 1000,
        'toMeters': i == 5 ? 5200 : (i + 1) * 1000,
        'fullKilometer': i < 5,
        'ourSeconds': completed ? (i == 5 ? 25 : 35) : null,
        'ghostSeconds': i == 5 ? 30 : 40,
        'deltaSeconds': completed ? 5 : null,
        'cumulativeDeltaSeconds': completed ? (i + 1) * 5 : null,
        'unavailableReason': completed ? null : 'POSITION_UNCONFIRMED',
      },
  ],
};
RunSnapshot snapshot(Map<String, dynamic>? result) => RunSnapshot(
  state: RunState.finished,
  sessionId: ghostId,
  startedAt: ghostEpoch,
  elapsed: const Duration(seconds: 900),
  active: const Duration(seconds: 800),
  distanceMeters: 9000,
  inputs: const [],
  ghost: result,
  ghostPending: result == null,
  storageStatus: '기록 저장됨',
  averageCadence: 222,
);

class ComparisonServer implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Future<ResponseBody> Function(RequestOptions)? response;
  Object? data;
  bool cancelled = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancellation,
  ) async {
    requests.add(o);
    cancellation?.then((_) {
      cancelled = true;
    });
    return response != null
        ? response!(o)
        : ResponseBody.fromString(
            jsonEncode({'data': data}),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('packages/wadadak_design_system/Pretendard');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      font.addFont(
        rootBundle.load(
          'packages/wadadak_design_system/assets/fonts/Pretendard-$weight.otf',
        ),
      );
    }
    await font.load();
  });
  test('reference segments include separate tail and preserve independent missing values', () {
    final d = GhostComparison.fromJson(comparisonJson());
    expect(d.segments.last.label, '5–5.2km');
    expect(d.segments.first.label, '0–1km');
    expect(d.segments.fold<int>(0, (n, s) => n + s.delta!), 30);
    expect(d.segments.last.pace(true), 125);
    final incomplete = GhostComparison.fromJson(
      comparisonJson(completed: false, outcome: 'LOSE'),
    );
    expect(incomplete.ours!.elapsedSeconds, isNull);
    expect(incomplete.segments.first.ghost, 40);
    expect(incomplete.segments.first.cumulative, isNull);
  });
  test(
    'rejects foreign verdict, invalid boundaries and public private sensors',
    () {
      final wrong = comparisonJson();
      (wrong['result'] as Map)['sessionId'] = 'other';
      expect(() => GhostComparison.fromJson(wrong), throwsFormatException);
      final invalid = comparisonJson();
      (invalid['segments'] as List)[5]['fromMeters'] = 4000;
      expect(() => GhostComparison.fromJson(invalid), throwsFormatException);
      final public = comparisonJson(kind: 'PUBLIC_COURSE');
      (public['ghost'] as Map)['averageCadence'] = 170;
      expect(() => GhostComparison.fromJson(public), throwsFormatException);
    },
  );
  test('comparison API preserves owner options and result identity', () async {
    final server = ComparisonServer()..data = comparisonJson();
    final client = RunApiClient(
      Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    );
    expect(
      (await GhostComparisonApi(client).get('alice', ghostId)).sourceId,
      sourceId,
    );
    expect(server.requests.single.extra['runOwner'], 'alice');
    expect(
      server.requests.single.path,
      '/api/v1/runs/sessions/$ghostId/ghost/result/comparison',
    );
    await expectLater(
      GhostComparisonApi(client).get('alice', 'another'),
      throwsFormatException,
    );
  });
  testWidgets(
    'comparison loading has a 15 second deadline and cancels request',
    (tester) async {
      final gate = Completer<ResponseBody>();
      final server = ComparisonServer()..response = (_) => gate.future;
      final api = GhostComparisonApi(
        RunApiClient(
          Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
        ),
      );
      final outcome = expectLater(
        api.get('alice', ghostId),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'GHOST_COMPARISON_TIMEOUT',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await outcome;
      await tester.pump();
      expect(server.cancelled, isTrue);
      gate.complete(ResponseBody.fromString('{}', 200));
      await tester.pump();
    },
  );
  test(
    'free retry prepares exact original and does not start a session',
    () async {
      final d = comparisonJson(kind: 'OWN_FREE')..['distanceMeters'] = 1112;
      d['segments'] = [
        {
          'number': 1,
          'fromMeters': 0,
          'toMeters': 1000,
          'fullKilometer': true,
          'ourSeconds': 180,
          'ghostSeconds': 200,
          'deltaSeconds': 20,
          'cumulativeDeltaSeconds': 20,
        },
        {
          'number': 2,
          'fromMeters': 1000,
          'toMeters': 1112,
          'fullKilometer': false,
          'ourSeconds': 20,
          'ghostSeconds': 30,
          'deltaSeconds': 10,
          'cumulativeDeltaSeconds': 30,
        },
      ];
      final server = ComparisonServer()
        ..data = preparation(version: 'GHOST_PLAYBACK_FREE_V2');
      final p = await GhostRetryPreparation(
        RunApiClient(
          Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
        ),
      ).prepare('alice', GhostComparison.fromJson(d));
      expect(p.free!.replay.sourceId, sourceId);
      expect(p.course, isNull);
      expect(server.requests.single.method, 'GET');
      expect(
        server.requests.single.queryParameters['playbackVersion'],
        'GHOST_PLAYBACK_FREE_V2',
      );
    },
  );
  test(
    'public retry preserves period and never substitutes an unavailable source',
    () async {
      final d = comparisonJson(kind: 'PUBLIC_COURSE')
        ..['distanceMeters'] = 1112;
      d['segments'] = [
        {
          'number': 1,
          'fromMeters': 0,
          'toMeters': 1000,
          'fullKilometer': true,
          'ourSeconds': 180,
          'ghostSeconds': 200,
          'deltaSeconds': 20,
          'cumulativeDeltaSeconds': 20,
        },
        {
          'number': 2,
          'fromMeters': 1000,
          'toMeters': 1112,
          'fullKilometer': false,
          'ourSeconds': 20,
          'ghostSeconds': 30,
          'deltaSeconds': 10,
          'cumulativeDeltaSeconds': 30,
        },
      ];
      final server = ComparisonServer()
        ..data = {
          'publicPeriod': 'WEEK',
          'candidate': {
            'rank': 1,
            'runRecordId': sourceId,
            'courseElapsedSeconds': 230,
          },
          'playback': ghostApproval(ghostIntent())['playback'],
        };
      final retry = GhostRetryPreparation(
        RunApiClient(
          Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
        ),
      );
      final p = await retry.prepare('alice', GhostComparison.fromJson(d));
      expect(p.course!.publicPeriod, 'WEEK');
      expect(server.requests.single.queryParameters, {
        'courseId': courseId,
        'period': 'WEEK',
      });
      server.response = (_) async => ResponseBody.fromString(
        '{"code":"RUN-002","message":"missing"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
      await expectLater(
        retry.prepare('alice', GhostComparison.fromJson(d)),
        throwsA(isA<ApiException>()),
      );
      expect(server.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> j, {
    double width = 402,
    GlobalKey? capture,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: WdTheme.light(),
          home: RepaintBoundary(
            key: capture,
            child: GhostResultScreen(
              run: snapshot((j['result'] as Map).cast<String, dynamic>()),
              comparison: GhostComparison.fromJson(j),
              onAgain: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 402.0]) {
    testWidgets(
      'duel metrics and partial segment detail fit ${width.toInt()}px',
      (tester) async {
        final key = GlobalKey();
        await mount(tester, comparisonJson(), width: width, capture: key);
        expect(find.text('내 코스 최고 기록 경신'), findsNothing);
        expect(find.text('대결 중 최고 구간'), findsOneWidget);
        expect(find.text('222'), findsNothing);
        expect(find.text('174'), findsOneWidget);
        final path = Platform.environment['GHOST_RESULT_SCREENSHOT_DIR'];
        if (path != null) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final picture = await boundary.toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$path/ghost-result-${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
        await tester.tap(find.text('구간 상세'));
        await tester.pumpAndSettle();
        expect(find.text('대결 구간 상세'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('5–5.2km · 마지막 구간'), 400);
        expect(find.text('5–5.2km · 마지막 구간'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('incomplete loss shows reason and never a finish difference', (
    tester,
  ) async {
    await mount(tester, comparisonJson(completed: false, outcome: 'LOSE'));
    expect(find.text('100초'), findsNothing);
    expect(find.text('고스트 도착 후 완주 전에 대결을 종료했어요.'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('legacy result retains verdict and explains missing comparison', (
    tester,
  ) async {
    final j = comparisonJson()
      ..['status'] = 'LEGACY_NO_DETAIL'
      ..['ours'] = null
      ..['ghost'] = null
      ..['segments'] = [];
    await mount(tester, j);
    expect(find.text('승리'), findsOneWidget);
    expect(find.textContaining('이전 기록에는'), findsOneWidget);
    expect(find.byType(GhostGapChart), findsNothing);
  });
  testWidgets('pending result has an explicit retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: WdTheme.light(),
        home: GhostResultScreen(run: snapshot(null), onRetry: () => retries++),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('판정 다시 확인'));
    expect(retries, 1);
    expect(find.text('서버 판정 대기'), findsOneWidget);
  });
}
