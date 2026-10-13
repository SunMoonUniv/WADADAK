import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'region_api_client.dart';

/// 전체 랭킹 기간(Asia/Seoul). 이번 주는 월요일 00:00, 이번 달은 1일 00:00부터다.
enum RankingPeriod {
  week('WEEK'),
  month('MONTH'),
  all('ALL');

  const RankingPeriod(this.apiName);
  final String apiName;
}

/// 순위 한 줄.
class DistanceRankingEntry {
  DistanceRankingEntry.fromJson(Map json)
      : rank = json['rank'] as int,
        nickname = json['nickname'] as String,
        profileImageUrl = json['profileImageUrl'] as String?,
        distanceMeters = json['distanceMeters'] as int,
        runCount = json['runCount'] as int,
        weeklyAverageMeters = json['weeklyAverageMeters'] as int;

  final int rank;
  final String nickname;
  final String? profileImageUrl;
  final int distanceMeters;

  /// 그 기간에 등록된 기록 수.
  final int runCount;

  /// 누적 거리 ÷ 첫 기록이 등록된 주부터 이번 주까지의 주 수.
  final int weeklyAverageMeters;
}

enum MyRankStatus {
  ranked('RANKED'),

  /// 그 기간 기록이 없다.
  noRecord('NO_RECORD'),

  /// 내 정보 공개를 꺼서 순위에서 빠졌다. 순위 대신 `비공개 중`을 표시한다.
  private('PRIVATE'),

  /// 지역 탭에서 이번 주 내 활동 지역이 아닌 지역을 보고 있다.
  otherRegion('OTHER_REGION');

  const MyRankStatus(this.apiName);
  final String apiName;
}

/// 내 순위. [status]가 [MyRankStatus.ranked]가 아니면 [rank] · [topPercent] · [lastWeekRank]는 null이다.
class MyDistanceRanking {
  MyDistanceRanking.fromJson(Map json)
      : status = MyRankStatus.values.firstWhere((s) => s.apiName == json['status']),
        rank = json['rank'] as int?,
        distanceMeters = json['distanceMeters'] as int?,
        thisWeekDistanceMeters = json['thisWeekDistanceMeters'] as int?,
        topPercent = json['topPercent'] as int?,
        lastWeekRank = json['lastWeekRank'] as int?;

  final MyRankStatus status;
  final int? rank;

  /// 그 기간 내 거리. 기록이 없으면 null.
  final int? distanceMeters;

  /// 이번 주 내 거리(전체 랭킹 탭).
  final int? thisWeekDistanceMeters;

  /// 상위 비율(%, 전체 랭킹 탭).
  final int? topPercent;

  /// 지난주 마지막 순위(지역 탭). 지난주에 순위가 없었으면 null.
  final int? lastWeekRank;
}

/// 전체 랭킹 탭(E1). 매일 자정에 계산한 값이다.
class DistanceRankingSummary {
  DistanceRankingSummary.fromJson(Map json)
      : participantCount = json['participantCount'] as int,
        me = MyDistanceRanking.fromJson(json['me'] as Map),
        top = _entries(json['top']),
        nextCursor = json['nextCursor'] as String?;

  /// 그 기간에 기록이 있는 내 정보 공개 회원 수.
  final int participantCount;
  final MyDistanceRanking me;

  /// 시상대 1~3위.
  final List<DistanceRankingEntry> top;

  /// 4위부터 이어 받을 커서. 더 없으면 null.
  final String? nextCursor;
}

/// 지역 주간 랭킹(I2 · I5). 매일 자정에 계산하고 매주 월요일 00:00에 새로 시작한다.
class RegionWeeklyRanking {
  RegionWeeklyRanking.fromJson(Map json)
      : region = Region.fromJson(json['region'] as Map),
        weekStart = DateTime.parse(json['weekStart'] as String),
        participantCount = json['participantCount'] as int,
        me = MyDistanceRanking.fromJson(json['me'] as Map),
        top = _entries(json['top']),
        nextCursor = json['nextCursor'] as String?;

  final Region region;

  /// 이번 주 월요일.
  final DateTime weekStart;
  final int participantCount;
  final MyDistanceRanking me;

  /// 상위 5줄.
  final List<DistanceRankingEntry> top;

  /// 6위부터 이어 받을 커서. 더 없으면 null.
  final String? nextCursor;
}

/// 커서로 이어 받은 순위 한 묶음.
typedef RankingPage = ({List<DistanceRankingEntry> entries, String? nextCursor});

List<DistanceRankingEntry> _entries(Object? json) =>
    [for (final entry in json as List) DistanceRankingEntry.fromJson(entry as Map)];

/// 랭킹 API(`/api/v1/rankings`). 모두 로그인이 필요하다.
class RankingApiClient {
  RankingApiClient(this._dio);

  final Dio _dio;
  static const _base = '/api/v1/rankings';

  Future<DistanceRankingSummary> distance(RankingPeriod period) async => DistanceRankingSummary.fromJson(
      await callApi(() => _dio.get('$_base/distance', queryParameters: {'period': period.apiName})) as Map);

  Future<RankingPage> distanceEntries(RankingPeriod period, String cursor) async => _page(await callApi(
      () => _dio.get('$_base/distance/entries', queryParameters: {'period': period.apiName, 'cursor': cursor})));

  /// [regionCode]가 null이면 내 활동 지역. 시·군·구가 아니면 RANKING-002.
  Future<RegionWeeklyRanking> regionWeekly(String? regionCode) async => RegionWeeklyRanking.fromJson(await callApi(
      () => _dio.get('$_base/distance/regions/weekly', queryParameters: {'regionCode': ?regionCode})) as Map);

  Future<RankingPage> regionWeeklyEntries(String? regionCode, String cursor) async => _page(await callApi(() => _dio
      .get('$_base/distance/regions/weekly/entries', queryParameters: {'regionCode': ?regionCode, 'cursor': cursor})));

  static RankingPage _page(Object? data) {
    data as Map;
    return (entries: _entries(data['content']), nextCursor: data['nextCursor'] as String?);
  }
}

final rankingApiClientProvider = Provider<RankingApiClient>((ref) => RankingApiClient(ref.watch(dioProvider)));
