import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:wadadak/core/api/region_api_client.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/map_view.dart';
import 'package:wadadak/main.dart';

import 'fakes.dart';

const _seongbuk = {'code': '1129000000', 'name': '성북구', 'fullName': '서울특별시 성북구'};
const _asan = {'code': '4420000000', 'name': '아산시', 'fullName': '충청남도 아산시'};

Map<String, Object?> _entry(int rank, String nickname, int meters) => {
      'rank': rank,
      'nickname': nickname,
      'profileImageUrl': null,
      'distanceMeters': meters,
      'runCount': 3,
      'weeklyAverageMeters': meters ~/ 24,
    };

/// [from]위부터 [to]위까지 "러너{순위}". 거리는 [meters]부터 순위마다 1km씩 준다.
List<Map<String, Object?>> _runners(int from, int to, int meters) =>
    [for (var rank = from; rank <= to; rank++) _entry(rank, '러너$rank', meters - (rank - from) * 1000)];

RankingPage _page(List<Map<String, Object?>> entries, String? nextCursor) =>
    (entries: [for (final entry in entries) DistanceRankingEntry.fromJson(entry)], nextCursor: nextCursor);

/// 전체 랭킹: 누적 25명 중 나 24위, 이번 주는 아무도 없다.
/// 지역 주간: 성북구(내 지역) 30명 중 나 12위, 아산시 3명.
class FakeRankingApi extends Fake implements RankingApiClient {
  final calls = <String>[];

  /// 다음 호출 한 번을 실패시킨다.
  ApiException? failNext;

  void _call(String call) {
    calls.add(call);
    final error = failNext;
    failNext = null;
    if (error != null) throw error;
  }

  @override
  Future<DistanceRankingSummary> distance(RankingPeriod period) async {
    _call('distance ${period.apiName}');
    if (period == RankingPeriod.week) {
      return DistanceRankingSummary.fromJson({
        'participantCount': 0,
        'me': {'status': 'NO_RECORD'},
        'top': const [],
        'nextCursor': null,
      });
    }
    return DistanceRankingSummary.fromJson({
      'participantCount': 25,
      'me': {
        'status': 'RANKED',
        'rank': 24,
        'nickname': 'wonehgus',
        'distanceMeters': 128000,
        'thisWeekDistanceMeters': 48200,
        'topPercent': 96,
      },
      'top': [_entry(1, '러너_하늘', 1284000), _entry(2, '러너_민', 1102000), _entry(3, '성북러너', 987000)],
      'nextCursor': '3',
    });
  }

  @override
  Future<RankingPage> distanceEntries(RankingPeriod period, String cursor) async {
    _call('distance entries $cursor');
    return cursor == '3' ? _page(_runners(4, 23, 912000), '23') : _page(_runners(24, 25, 128000), null);
  }

  @override
  Future<RegionWeeklyRanking> regionWeekly(String? regionCode) async {
    _call('region ${regionCode ?? 'mine'}');
    final asan = regionCode == _asan['code'];
    return RegionWeeklyRanking.fromJson({
      'region': asan ? _asan : _seongbuk,
      'weekStart': '2026-10-12',
      'participantCount': asan ? 3 : 30,
      'me': asan
          ? {'status': 'OTHER_REGION'}
          : {'status': 'RANKED', 'rank': 12, 'nickname': 'wonehgus', 'distanceMeters': 48200, 'lastWeekRank': 19},
      'top': asan ? _runners(1, 3, 30000) : [_entry(1, '러너_하늘', 102400), ..._runners(2, 5, 88100)],
      'nextCursor': asan ? null : '5',
    });
  }

  @override
  Future<RankingPage> regionWeeklyEntries(String? regionCode, String cursor) async {
    _call('region entries $cursor');
    return cursor == '5' ? _page(_runners(6, 25, 66200), '25') : _page(_runners(26, 30, 20000), null);
  }
}

void main() {
  late FakeRankingApi api;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openRanking(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(402, 874)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(MemoryTokenStorage(testTokens)),
        memberApiClientProvider.overrideWithValue(FakeMemberApi()),
        rankingApiClientProvider.overrideWithValue(api),
        regionApiClientProvider.overrideWithValue(FakeRegionApi()),
        mapEngineProvider.overrideWithValue(MapEngine.dev),
        courseApiClientProvider.overrideWithValue(FakeCourseApi()),
      ],
      child: const WadadakApp(),
    ));
    await tester.pumpAndSettle();
    await tap(tester, find.text('랭킹'));
  }

  setUp(() => api = FakeRankingApi());

  testWidgets('whole ranking shows the podium and my rank, and loads more runners at the end', (tester) async {
    await openRanking(tester);

    expect(find.text('러너 25명'), findsOneWidget);
    expect(find.text('1,284.0 km'), findsOneWidget);
    expect(find.text('이번 주 +48.2 km · 상위 96%'), findsOneWidget);
    expect(find.text('나 (wonehgus)'), findsOneWidget, reason: 'Figma E1');
    expect(find.text('128.0 km'), findsOneWidget);
    expect(find.text('러너4'), findsOneWidget);
    expect(find.text('주 평균 38 km'), findsWidgets);
    expect(find.text('러너24'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(find.text('러너25'), findsOneWidget);
    expect(api.calls, ['distance ALL', 'distance entries 3', 'distance entries 23']);
  });

  testWidgets('another period loads its own ranking', (tester) async {
    await openRanking(tester);

    await tap(tester, find.text('이번 주'));

    expect(find.text('러너 0명'), findsOneWidget);
    expect(find.text('아직 달린 러너가 없어요'), findsOneWidget);
    expect(api.calls.last, 'distance WEEK');
  });

  testWidgets('offers retry when the ranking cannot be loaded', (tester) async {
    api.failNext = const ApiException(ApiException.network, '네트워크에 연결할 수 없어요.');
    await openRanking(tester);

    expect(find.text('네트워크에 연결할 수 없어요.'), findsOneWidget);
    await tap(tester, find.text('다시 시도'));

    expect(find.text('러너 25명'), findsOneWidget);
  });

  testWidgets('weekly region ranking: top 5, the full list, and another region from search', (tester) async {
    await openRanking(tester);
    await tap(tester, find.text('지역 주간 랭킹'));

    expect(find.text('성북구 · 지난주 19위 ▲7'), findsOneWidget);
    expect(find.text('나 (wonehgus)'), findsOneWidget);
    expect(find.text('성북구 순위 · 이번 주'), findsOneWidget);
    expect(find.text('러너5'), findsOneWidget);
    expect(find.text('러너6'), findsNothing);

    // I5: 1위부터 이어서 받는다.
    await tap(tester, find.text('20명 더 보기'));
    expect(find.text('10월 2주차'), findsOneWidget);
    expect(find.text('전체 순위 30명'), findsOneWidget);
    expect(find.text('12위'), findsOneWidget);
    expect(find.text('러너6'), findsOneWidget);
    expect(find.text('러닝 3회 · 성북구'), findsWidgets);

    // I6: 검색해서 고르면 I5로 돌아와 그 지역을 본다. 내 활동 지역이 아니라 내 순위 카드는 없다.
    await tap(tester, find.text('⌕ 지역 검색'));
    expect(find.text('서울 · 활동 지역 ✓'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '아산');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('충남'), findsOneWidget);
    await tap(tester, find.text('아산시'));

    expect(find.text('전체 순위 3명'), findsOneWidget);
    expect(find.textContaining('나 ('), findsNothing);

    // I2도 같은 지역을 본다.
    await tap(tester, find.bySemanticsLabel('뒤로 가기'));
    expect(find.text('아산시 순위 · 이번 주'), findsOneWidget);
    expect(find.textContaining('더 보기'), findsNothing);

    // 최근 선택에 남고, 내 지역을 고르면 돌아간다.
    await tap(tester, find.text('⌕ 지역 검색'));
    expect(find.text('최근 선택'), findsOneWidget);
    await tap(tester, find.text('성북구'));

    expect(find.text('성북구 순위 · 이번 주'), findsOneWidget);
    expect(api.calls, contains('region 4420000000'));
  });
}
