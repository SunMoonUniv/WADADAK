import 'dart:async';
import 'dart:convert';

import 'package:wadadak/core/api/api_client.dart';
import 'package:wadadak/core/api/course_api_client.dart';
import 'package:wadadak/core/api/member_api_client.dart';
import 'package:wadadak/core/api/ranking_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wadadak/core/api/region_api_client.dart';
import 'package:wadadak/core/api/review_api_client.dart';
import 'package:wadadak/core/api/upload_form.dart';
import 'package:wadadak/core/auth/social_login.dart';
import 'package:wadadak/core/auth/token_storage.dart';
import 'package:wadadak/core/map/geo_point.dart';
import 'package:wadadak/core/permissions/device_setup.dart';
import 'package:wadadak/core/upload/photo_uploader.dart';
import 'package:wadadak/features/home/my_location.dart';
import 'package:wadadak/features/onboarding/permission_screen.dart';

const testTokens = AuthTokens(accessToken: 'access', refreshToken: 'refresh');

/// 지도 · 목록 테스트용 코스(카드 값). 이름 · 경로 말고는 정해 둔 값이다.
CourseListItem testCourse(
  String name, {
  String? courseId,
  List<GeoPoint> route = const [GeoPoint(37.5666, 126.9784), GeoPoint(37.5700, 126.9800)],
  int distanceMeters = 1000,
  Difficulty difficulty = Difficulty.easy,
  List<CourseTag> tags = const [],
  CourseType courseType = CourseType.custom,
  DateTime? expiresAt,
  double? averageRating,
  int reviewCount = 0,
  int activeRunners = 0,
}) =>
    CourseListItem(
      courseId: courseId ?? 'id-$name',
      name: name,
      distanceMeters: distanceMeters,
      difficulty: difficulty,
      tags: tags,
      courseType: courseType,
      expiresAt: expiresAt ?? DateTime.utc(2026, 11, 13, 14, 59, 59),
      averageRating: averageRating,
      reviewCount: reviewCount,
      activeRunners: activeRunners,
      route: route,
    );

class MemoryTokenStorage implements TokenStorage {
  MemoryTokenStorage([this.tokens]);

  AuthTokens? tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;

  @override
  Future<void> clear() async => tokens = null;
}

class FakeMemberApi implements MemberApiClient {
  LoginResult loginResult = const LoginSignupRequired('signup-token');
  ApiException? signupError;
  Map<String, Object?>? signedUp;
  int logouts = 0;

  /// 프로필 사진 업로드 폼을 받을 때 보낸 가입 토큰
  final photoFormTokens = <String>[];

  @override
  Future<LoginResult> login(SocialProvider provider, String socialToken) async => loginResult;

  @override
  Future<AuthTokens> signup({
    required String signupToken,
    required Agreements agreements,
    required String nickname,
    required String? bio,
    required String regionCode,
    required String? affiliation,
    required RunningExperience runningExperience,
    required String? profileImageKey,
    required BodyInfo? bodyInfo,
  }) async {
    if (signupError != null) throw signupError!;
    signedUp = {
      'signupToken': signupToken,
      'agreements': agreements.toJson(),
      'nickname': nickname,
      'bio': bio,
      'regionCode': regionCode,
      'affiliation': affiliation,
      'runningExperience': runningExperience.apiName,
      'profileImageKey': profileImageKey,
      'bodyInfo': bodyInfo?.toJson(),
    };
    return testTokens;
  }

  @override
  Future<UploadForm> signupPhotoUploadForm(String signupToken) async {
    photoFormTokens.add(signupToken);
    return UploadForm.fromJson({'url': 'https://files.test/wadadak', 'key': 'member/photo.jpg', 'fields': <String, String>{}});
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async => testTokens;

  @override
  Future<void> logout(String refreshToken) async => logouts++;
}

/// 1×1 PNG. 미리보기가 그림으로 읽을 수 있는 사진이다.
final testPhoto = XFile.fromData(
  base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='),
  name: 'me.png',
);

/// 고르면 [photo] 한 장. 올리면 서버 업로드 폼을 받아 그 키를 돌려준다(저장소에는 보내지 않는다).
class FakePhotoUploader implements PhotoUploader {
  XFile? photo;
  final uploaded = <XFile>[];

  @override
  Future<List<XFile>> pick({int limit = 1}) async => [?photo];

  @override
  Future<String> upload(XFile photo, Future<UploadForm> Function() requestForm) async {
    uploaded.add(photo);
    return (await requestForm()).key;
  }
}

class FakeSocialLogin implements SocialLogin {
  @override
  Future<String> signIn(SocialProvider provider) async => 'social-token';
}

/// 성북구 · 아산시만 있다. 서버처럼 이름이나 상위 구역 이름에 검색어가 들어가면 찾는다.
class FakeRegionApi implements RegionApiClient {
  static const _regions = [
    {'code': '1129000000', 'name': '성북구', 'fullName': '서울특별시 성북구'},
    {'code': '4420000000', 'name': '아산시', 'fullName': '충청남도 아산시'},
  ];

  @override
  Future<List<Region>> search(String query) async =>
      [for (final region in _regions) if (region['fullName']!.contains(query)) Region.fromJson(region)];
}

class FakeRunPermissions implements RunPermissions {
  int requests = 0;

  @override
  Future<void> request() async => requests++;
}

class FakeCourseApi implements CourseApiClient {
  RegistrationQuota quota = const RegistrationQuota(
    custom: TypeQuota(limit: 1, remaining: 1),
    gps: TypeQuota(limit: 3, remaining: 3),
  );
  ApiException? routeError;
  List<GeoPoint>? sentPoints;

  /// 이미 있는 코스 이름. 서버처럼 공백 · 대소문자를 무시하고 비교한다.
  Set<String> takenNames = {};
  ApiException? registerError;

  /// 있으면 끝날 때까지 등록 응답을 미룬다(등록 중 화면).
  Completer<void>? registerGate;
  final registrations = <FakeRegistration>[];

  /// 지도 범위와 상관없이 돌려줄 코스. 필터는 거리 · 난이도 · 최소 평점 · 특징 · 유형을 서버처럼 적용한다.
  /// G6에서 고른 검색어 · 지역([CourseSearchPick])은 이름에 검색어가 들어갔는지만 본다(코스에 지역 값이 없다).
  List<CourseListItem> onMap = [];
  ApiException? mapError;
  final mapRequests = <({GeoPoint southWest, GeoPoint northEast, CourseFilter filter, CourseSearchPick? pick})>[];

  /// 지도 범위 · 단위 · 필터와 상관없이 돌려줄 지역별 코스 수.
  List<RegionCount> regions = [];
  ApiException? regionsError;
  final regionRequests =
      <({GeoPoint southWest, GeoPoint northEast, RegionLevel level, CourseFilter filter, CourseSearchPick? pick})>[];

  @override
  Future<RegistrationQuota> registrationQuota() async => quota;

  /// 코스 상세(B1). 없는 ID는 서버처럼 COURSE-001이다. [detailError]가 있으면 그 오류다.
  Map<String, CourseDetail> details = {};
  ApiException? detailError;
  final detailRequests = <String>[];

  @override
  Future<CourseDetail> courseDetail(String courseId) async {
    detailRequests.add(courseId);
    if (detailError != null) throw detailError!;
    return details[courseId] ??
        (throw const ApiException(CourseApiClient.courseNotFoundCode, '코스를 찾을 수 없습니다.', status: 404));
  }

  /// 서버처럼 입력점을 그대로 잇고, 끝점에 1km 표지 하나를 둔다.
  @override
  Future<GeneratedRoute> generateRoute(List<GeoPoint> anchorPoints) async {
    sentPoints = anchorPoints;
    if (routeError != null) throw routeError!;
    return GeneratedRoute(
      anchorPoints: anchorPoints,
      route: anchorPoints,
      distanceMeters: GeoPoint.pathLength(anchorPoints).round(),
      distanceMarkers: [DistanceMarker(1, anchorPoints.last)],
    );
  }

  @override
  Future<bool> isNameAvailable(String name) async => !takenNames.map(_nameKey).contains(_nameKey(name));

  @override
  Future<RegisteredCourse> registerCustom({
    required String idempotencyKey,
    required List<GeoPoint> anchorPoints,
    required String name,
    required Difficulty difficulty,
    required Set<CourseTag> tags,
  }) async {
    registrations.add((
      idempotencyKey: idempotencyKey,
      anchorPoints: anchorPoints,
      name: name,
      difficulty: difficulty,
      tags: {...tags},
    ));
    await registerGate?.future;
    if (registerError != null) throw registerError!;
    return RegisteredCourse(courseId: 'course-${registrations.length}', name: name, startPoint: anchorPoints.first);
  }

  @override
  Future<CourseMap> mapCourses({
    required GeoPoint southWest,
    required GeoPoint northEast,
    CourseFilter filter = CourseFilter.none,
    CourseSearchPick? pick,
  }) async {
    mapRequests.add((southWest: southWest, northEast: northEast, filter: filter, pick: pick));
    if (mapError != null) throw mapError!;
    final courses = [for (final course in onMap) if (matches(course, filter) && _picked(course, pick)) course];
    return CourseMap(totalCount: courses.length, courses: courses);
  }

  /// 서버처럼 [course]가 [filter]에 맞나(FIL-02~05). 최소 평점이 있으면 리뷰가 없는 코스는 빠진다.
  static bool matches(CourseListItem course, CourseFilter filter) =>
      course.distanceMeters >= (filter.minDistanceMeters ?? 0) &&
      course.distanceMeters <= (filter.maxDistanceMeters ?? course.distanceMeters) &&
      (filter.difficulties.isEmpty || filter.difficulties.contains(course.difficulty)) &&
      (filter.minRating == null || (course.averageRating ?? -1) >= filter.minRating!) &&
      course.tags.toSet().containsAll(filter.tags) &&
      (filter.courseType == null || filter.courseType == course.courseType);

  static bool _picked(CourseListItem course, CourseSearchPick? pick) =>
      pick == null || _nameKey(course.name).contains(_nameKey(pick.query));

  @override
  Future<RegionCounts> regionCounts({
    required GeoPoint southWest,
    required GeoPoint northEast,
    required RegionLevel level,
    CourseFilter filter = CourseFilter.none,
    CourseSearchPick? pick,
  }) async {
    regionRequests.add((southWest: southWest, northEast: northEast, level: level, filter: filter, pick: pick));
    if (regionsError != null) throw regionsError!;
    return RegionCounts(totalCount: regions.fold(0, (sum, region) => sum + region.count), regions: regions);
  }

  /// 지도 범위 · 정렬과 상관없이 돌려줄 목록. 필터는 [matches]로 거른다.
  /// [listPageSize]개씩 쪽을 나누고, 커서는 다음 쪽 첫 위치다.
  List<CourseListItem> listed = [];
  int listPageSize = 20;
  ApiException? listError;
  final listRequests = <ListRequest>[];

  @override
  Future<CourseListPage> listCourses({
    required GeoPoint southWest,
    required GeoPoint northEast,
    CourseFilter filter = CourseFilter.none,
    CourseSearchPick? pick,
    CourseListSort sort = CourseListSort.initial,
    CoursePeriod? period,
    GeoPoint? origin,
    String? cursor,
  }) async {
    listRequests.add((
      southWest: southWest,
      northEast: northEast,
      filter: filter,
      pick: pick,
      sort: sort,
      period: period,
      origin: origin,
      cursor: cursor,
    ));
    if (listError != null) throw listError!;
    final courses = [for (final course in listed) if (matches(course, filter) && _picked(course, pick)) course];
    final from = cursor == null ? 0 : int.parse(cursor);
    final to = (from + listPageSize).clamp(0, courses.length);
    return CourseListPage(courses: courses.sublist(from, to), nextCursor: to < courses.length ? '$to' : null);
  }

  /// 검색할 코스. 서버처럼 공백 · 대소문자를 무시하고 이름에 검색어가 들어간 코스를 순서대로 돌려준다(정렬은 보지 않는다).
  /// [searchPageSize]개씩 쪽을 나누고, 커서는 다음 쪽 첫 위치다.
  List<CourseListItem> searchable = [];
  int searchPageSize = 20;
  ApiException? searchError;

  /// 있으면 끝날 때까지 검색 응답을 미룬다(받는 중 화면).
  Completer<void>? searchGate;
  final searchRequests = <({String query, CourseListSort sort, GeoPoint? origin, String? cursor})>[];

  @override
  Future<CourseSearchPage> searchCourses({
    required String query,
    CourseListSort sort = CourseListSort.initial,
    GeoPoint? origin,
    String? cursor,
  }) async {
    searchRequests.add((query: query, sort: sort, origin: origin, cursor: cursor));
    await searchGate?.future;
    if (searchError != null) throw searchError!;
    final key = _nameKey(query);
    final courses = [for (final course in searchable) if (_nameKey(course.name).contains(key)) course];
    final from = cursor == null ? 0 : int.parse(cursor);
    final to = (from + searchPageSize).clamp(0, courses.length);
    return CourseSearchPage(
      totalCount: courses.length,
      courses: courses.sublist(from, to),
      nextCursor: to < courses.length ? '$to' : null,
    );
  }

  /// G6 지역 검색 결과. 검색어와 상관없이 돌려준다.
  List<SearchRegion> searchedRegions = [];
  ApiException? searchRegionsError;

  /// 있으면 끝날 때까지 지역 검색 응답을 미룬다(받는 중 화면).
  Completer<void>? searchRegionsGate;
  final searchRegionRequests = <String>[];

  @override
  Future<List<SearchRegion>> searchRegions(String query) async {
    searchRegionRequests.add(query);
    await searchRegionsGate?.future;
    if (searchRegionsError != null) throw searchRegionsError!;
    return searchedRegions;
  }

  /// 1분 갱신(공통 7 · HCR-05)에 돌려줄 현재 러너 수(courseId → 러너 수). 여기 없는 코스는 서버처럼 응답에서 빠진다.
  Map<String, int> runners = {};
  ApiException? runnersError;

  /// 현재 러너 수를 물은 코스 ID들. 요청마다 하나다.
  final runnerRequests = <List<String>>[];

  @override
  Future<Map<String, int>> activeRunners(List<String> courseIds) async {
    runnerRequests.add(courseIds);
    if (runnersError != null) throw runnersError!;
    return {for (final id in courseIds) id: ?runners[id]};
  }

  static String _nameKey(String name) => name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

typedef ListRequest = ({
  GeoPoint southWest,
  GeoPoint northEast,
  CourseFilter filter,
  CourseSearchPick? pick,
  CourseListSort sort,
  CoursePeriod? period,
  GeoPoint? origin,
  String? cursor,
});

/// 홈의 현재 위치는 [location]이다. [allowed]가 아니면 권한을 물어야 받고, [error]가 있으면 물어도 못 받는다.
class FakeMyLocation implements MyLocation {
  FakeMyLocation({this.location, this.allowed = false, this.error});

  GeoPoint? location;
  bool allowed;
  DeviceSetupException? error;

  /// 권한을 물어서라도 받은 횟수(가까운순).
  int requests = 0;
  final openedSettings = <DeviceSettingsAction>[];

  /// 기기에 남은 마지막 위치. 권한이 있을 때만 준다.
  GeoPoint? last;

  /// 있으면 [ifAllowed]가 이것이 끝날 때까지 기다린다(지금 위치를 받는 데 걸리는 시간).
  Completer<void>? fix;

  @override
  Future<GeoPoint?> ifAllowed() async {
    await fix?.future;
    return allowed ? location : null;
  }

  @override
  Future<GeoPoint?> lastIfAllowed() async => allowed ? last : null;

  @override
  Future<GeoPoint> request() async {
    requests++;
    if (error != null) throw error!;
    allowed = true;
    return location!;
  }

  @override
  Future<void> openSettings(DeviceSettingsAction action) async => openedSettings.add(action);
}

typedef FakeRegistration = ({
  String idempotencyKey,
  List<GeoPoint> anchorPoints,
  String name,
  Difficulty difficulty,
  Set<CourseTag> tags,
});

/// 코스 리뷰를 읽기만 하는 리뷰 API(B1 · B8, B8에서 여는 G2). 오류를 넣으면 그 요청이 실패한다.
class FakeCourseReviewApi extends Fake implements ReviewApiClient {
  FakeCourseReviewApi([this.result]);

  /// 요약. 없으면 리뷰 0개다.
  ReviewSummary? result;
  ApiException? error;
  int requests = 0;

  /// 목록이 돌려줄 카드. 사진 조건이면 사진 있는 카드만 준다. 정렬은 [listRequests]로 확인한다.
  List<ReviewCard> cards = [];
  ApiException? listError;
  /// 있으면 목록 응답이 이것이 끝날 때까지 늦는다.
  Completer<void>? listGate;
  final listRequests = <({ReviewSort sort, bool photoOnly, bool excludeMine})>[];

  @override
  Future<ReviewSummary> summary(String courseId) async {
    requests++;
    if (error != null) throw error!;
    return result ?? reviewSummary();
  }

  @override
  Future<ReviewPage> list(
    String courseId, {
    ReviewSort sort = ReviewSort.latest,
    bool photoOnly = false,
    bool excludeMine = false,
    String? cursor,
  }) async {
    listRequests.add((sort: sort, photoOnly: photoOnly, excludeMine: excludeMine));
    await listGate?.future;
    if (listError != null) throw listError!;
    return (
      cards: [
        for (final card in cards)
          if ((!excludeMine || !card.mine) && (!photoOnly || card.photos.isNotEmpty)) card,
      ],
      nextCursor: null,
    );
  }

  /// 내 리뷰도, 쓸 수 있는 기록도 없다.
  @override
  Future<MyReview> mine(String courseId) async =>
      MyReview.fromJson({'review': null, 'sourceRecord': null, 'sourceRecordDeleted': false, 'eligibleRecord': null});
}

/// 리뷰 카드 값. 2026-09-06 작성, 완주 100% · 4회 주행.
ReviewCard reviewCard(String nickname, {int rating = 5, bool mine = false, String content = '야간 조명이 밝아요.'}) =>
    ReviewCard.fromJson({
      'reviewId': 'review-$nickname',
      'memberId': 'member-$nickname',
      'nickname': nickname,
      'profileImageUrl': null,
      'mine': mine,
      'rating': rating,
      'safetyRating': rating,
      'roadRating': rating,
      'lightingRating': rating,
      'amenityRating': rating,
      'content': content,
      'tags': ['NIGHT_VIEW'],
      'photos': [],
      'bestProgressPercent': 100,
      'completedCount': 4,
      'createdAt': '2026-09-06T03:00:00Z',
    });

/// 리뷰 요약 값. 리뷰가 없으면 평균은 모두 null이다(서버와 같다).
/// [counts]는 5점부터 1점까지의 개수다. 없으면 모두 5점이다.
ReviewSummary reviewSummary({
  int count = 0,
  double? average,
  (double, double, double, double)? items,
  (int, int, int, int, int)? counts,
}) =>
    ReviewSummary.fromJson({
      'reviewCount': count,
      'averageRating': average,
      'ratingCounts': {
        'five': counts?.$1 ?? count,
        'four': counts?.$2 ?? 0,
        'three': counts?.$3 ?? 0,
        'two': counts?.$4 ?? 0,
        'one': counts?.$5 ?? 0,
      },
      'itemAverages': {
        'safety': items?.$1,
        'road': items?.$2,
        'lighting': items?.$3,
        'amenity': items?.$4,
      },
    });

/// 코스 랭킹만 받는 랭킹 API(B1 · B8 · B9 · G3). 기간마다 [summaries]를 돌려준다. 없는 기간은 참여 0명이다.
class FakeCourseRankingApi extends Fake implements RankingApiClient {
  FakeCourseRankingApi([Map<RankingPeriod, CourseRankingSummary>? summaries]) : summaries = summaries ?? {};

  Map<RankingPeriod, CourseRankingSummary> summaries;
  ApiException? error;

  /// 있으면 요약 응답이 이것이 끝날 때까지 늦는다.
  Completer<void>? gate;
  final summaryRequests = <RankingPeriod>[];

  /// G3 순위. 기간마다 1위부터의 전체 줄이고 [pageSize]씩 잘라 준다(서버와 같은 오프셋 커서).
  Map<RankingPeriod, List<CourseRankingEntry>> rows = {};
  int pageSize = 20;
  ApiException? entriesError;
  final entryRequests = <(RankingPeriod, String?)>[];

  @override
  Future<CourseRankingSummary> courseSummary(String courseId, RankingPeriod period) async {
    summaryRequests.add(period);
    await gate?.future;
    if (error != null) throw error!;
    return summaries[period] ?? courseRankingSummary();
  }

  @override
  Future<CourseRankingPage> courseEntries(String courseId, RankingPeriod period, {String? cursor}) async {
    entryRequests.add((period, cursor));
    await gate?.future;
    if (entriesError != null) throw entriesError!;
    final all = rows[period] ?? const <CourseRankingEntry>[];
    final from = int.parse(cursor ?? '0');
    final to = from + pageSize < all.length ? from + pageSize : all.length;
    return (entries: all.sublist(from, to), nextCursor: to < all.length ? '$to' : null);
  }
}

/// 코스 순위 한 줄. [pace]가 없으면 1km 코스처럼 시간과 같다. 2026-09-07 완주.
CourseRankingEntry courseRankingEntry(int rank, String nickname, int seconds,
        {int? pace, bool mine = false, String completedAt = '2026-09-07T01:00:00Z'}) =>
    CourseRankingEntry.fromJson({
      'rank': rank,
      'memberId': 'member-$nickname',
      'nickname': nickname,
      'profileImageUrl': null,
      'courseElapsedSeconds': seconds,
      'paceSecondsPerKm': pace ?? seconds,
      'completedAt': completedAt,
      'mine': mine,
    });

/// 코스 랭킹 요약 값. [me]가 없으면 그 기간 내 기록이 없다. [ghost]는 공개 고스트의 순위다.
CourseRankingSummary courseRankingSummary({
  int participants = 0,
  int? average,
  Map<String, Object?> me = const {'status': 'NO_RECORD'},
  List<CourseRankingEntry> top = const [],
  int? ghost,
}) =>
    CourseRankingSummary.fromJson({
      'participantCount': participants,
      'averageCourseElapsedSeconds': average,
      'me': me,
      'top': [
        for (final entry in top)
          {
            'rank': entry.rank,
            'memberId': entry.memberId,
            'nickname': entry.nickname,
            'profileImageUrl': entry.profileImageUrl,
            'courseElapsedSeconds': entry.courseElapsedSeconds,
            'paceSecondsPerKm': entry.paceSecondsPerKm,
            'completedAt': entry.completedAt.toIso8601String(),
            'mine': entry.mine,
          },
      ],
      'ghost': ghost == null
          ? null
          : {'runRecordId': 'run-$ghost', 'memberId': 'member-$ghost', 'rank': ghost, 'courseElapsedSeconds': 1452},
    });
