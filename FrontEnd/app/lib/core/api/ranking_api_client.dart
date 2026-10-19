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
        nickname = json['nickname'] as String?,
        profileImageUrl = json['profileImageUrl'] as String?,
        distanceMeters = json['distanceMeters'] as int?,
        thisWeekDistanceMeters = json['thisWeekDistanceMeters'] as int?,
        topPercent = json['topPercent'] as int?,
        lastWeekRank = json['lastWeekRank'] as int?;

  final MyRankStatus status;
  final int? rank;

  /// 내 닉네임 · 사진. 상태와 관계없이 오고, 서버가 프로필을 못 찾으면 null이다.
  final String? nickname;
  final String? profileImageUrl;

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

/// 코스 랭킹 한 줄(B9 · G3). 회원마다 그 기간 코스 총 소요시간이 가장 짧은 완주 기록 1건이다(정책 공통 6).
class CourseRankingEntry {
  CourseRankingEntry.fromJson(Map json)
      : rank = json['rank'] as int,
        memberId = json['memberId'] as String,
        nickname = json['nickname'] as String?,
        profileImageUrl = json['profileImageUrl'] as String?,
        courseElapsedSeconds = json['courseElapsedSeconds'] as int,
        paceSecondsPerKm = json['paceSecondsPerKm'] as int,
        completedAt = DateTime.parse(json['completedAt'] as String),
        mine = json['mine'] as bool;

  /// 코스 총 소요시간이 같으면 같은 순위이고 다음 순위는 그 인원만큼 건너뛴다(1 · 2 · 2 · 4).
  final int rank;
  final String memberId;

  /// 서버가 회원 정보를 받지 못하면 null. 탈퇴 회원은 `탈퇴한 사용자`.
  final String? nickname;
  final String? profileImageUrl;
  final int courseElapsedSeconds;

  /// km당 초.
  final int paceSecondsPerKm;
  final DateTime completedAt;

  /// 내 기록. 눌러도 프로필로 가지 않는다(G3-03).
  final bool mine;
}

/// 내 순위(B9-02). [status]가 [MyRankStatus.ranked]가 아니면 [rank] · [topPercent]는 null이다.
class MyCourseRanking {
  MyCourseRanking.fromJson(Map json)
      : status = MyRankStatus.values.firstWhere((s) => s.apiName == json['status']),
        rank = json['rank'] as int?,
        nickname = json['nickname'] as String?,
        profileImageUrl = json['profileImageUrl'] as String?,
        courseElapsedSeconds = json['courseElapsedSeconds'] as int?,
        paceSecondsPerKm = json['paceSecondsPerKm'] as int?,
        completedAt = switch (json['completedAt']) {
          final String at => DateTime.parse(at),
          _ => null,
        },
        topPercent = json['topPercent'] as int?;

  /// 순위 있음 · 그 기간 완주 기록 없음 · 내 정보 비공개(순위 대신 `비공개 중`).
  final MyRankStatus status;
  final int? rank;

  /// 내 닉네임 · 사진. 상태와 관계없이 오고, 서버가 프로필을 못 찾으면 null이다.
  final String? nickname;
  final String? profileImageUrl;

  /// 내 대표 기록. 그 기간 완주 기록이 없으면 null이다. 비공개여도 기록이 있으면 채운다.
  final int? courseElapsedSeconds;
  final int? paceSecondsPerKm;
  final DateTime? completedAt;

  /// 상위 비율(%). 순위 ÷ 참여 러너 수 × 100을 올림한다.
  final int? topPercent;
}

/// 고스트 대결 준비(C1)에 넘길 공개 고스트. 요청자 본인 기록은 빠진다.
class GhostCandidate {
  GhostCandidate.fromJson(Map json)
      : runRecordId = json['runRecordId'] as String,
        memberId = json['memberId'] as String,
        rank = json['rank'] as int,
        courseElapsedSeconds = json['courseElapsedSeconds'] as int;

  final String runRecordId;
  final String memberId;

  /// 랭킹 화면에 보이는 순위.
  final int rank;
  final int courseElapsedSeconds;
}

/// 코스 랭킹 요약(B9 · G3 상단, B1 · B8 · B9 · G3 고스트 대결 버튼). 내 정보 비공개 회원은 모두 빠진다.
class CourseRankingSummary {
  CourseRankingSummary.fromJson(Map json)
      : participantCount = json['participantCount'] as int,
        averageCourseElapsedSeconds = json['averageCourseElapsedSeconds'] as int?,
        me = MyCourseRanking.fromJson(json['me'] as Map),
        top = [for (final entry in json['top'] as List) CourseRankingEntry.fromJson(entry as Map)],
        ghost = switch (json['ghost']) {
          final Map ghost => GhostCandidate.fromJson(ghost),
          _ => null,
        };

  final int participantCount;

  /// 랭킹 평균 총 소요시간(러너별 대표 기록의 평균, 정수 초). 참여 0명이면 null.
  final int? averageCourseElapsedSeconds;
  final MyCourseRanking me;

  /// 상위 5줄. 첫 줄이 1위다.
  final List<CourseRankingEntry> top;

  /// 높은 순위부터 고른 첫 공개 고스트. 없으면 null이고 고스트 대결 버튼을 끈다.
  final GhostCandidate? ghost;
}

/// 커서로 받은 코스 순위 한 묶음(G3).
typedef CourseRankingPage = ({List<CourseRankingEntry> entries, String? nextCursor});

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

  /// 코스 랭킹 요약(B9 · G3 상단, 고스트 대결 버튼).
  Future<CourseRankingSummary> courseSummary(String courseId, RankingPeriod period) async =>
      CourseRankingSummary.fromJson(await callApi(() =>
          _dio.get('$_base/courses/${Uri.encodeComponent(courseId)}', queryParameters: {'period': period.apiName})) as Map);

  /// 코스 전체 순위(G3). [cursor]가 없으면 1위부터.
  Future<CourseRankingPage> courseEntries(String courseId, RankingPeriod period, {String? cursor}) async {
    final data = await callApi(() => _dio.get('$_base/courses/${Uri.encodeComponent(courseId)}/entries',
        queryParameters: {'period': period.apiName, 'cursor': ?cursor})) as Map;
    return (
      entries: [for (final entry in data['content'] as List) CourseRankingEntry.fromJson(entry as Map)],
      nextCursor: data['nextCursor'] as String?,
    );
  }

  static RankingPage _page(Object? data) {
    data as Map;
    return (entries: _entries(data['content']), nextCursor: data['nextCursor'] as String?);
  }
}

final rankingApiClientProvider = Provider<RankingApiClient>((ref) => RankingApiClient(ref.watch(dioProvider)));
