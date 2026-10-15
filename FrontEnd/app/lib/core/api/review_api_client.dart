import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'upload_form.dart';

/// 리뷰 태그(B2). 정해진 4개 중 여러 개를 고른다.
enum ReviewTag {
  nightView('NIGHT_VIEW', '야경 좋음'),
  fewSignals('FEW_SIGNALS', '신호 적음'),
  goodSurface('GOOD_SURFACE', '노면 좋음'),
  crowded('CROWDED', '붐빔');

  const ReviewTag(this.apiName, this.label);
  final String apiName;
  final String label;

  static ReviewTag? fromApi(String name) => values.where((tag) => tag.apiName == name).firstOrNull;
}

/// 리뷰 목록 정렬(B8-03 · G2). 같은 별점이면 최신순이다.
enum ReviewSort {
  latest('LATEST', '최신순'),
  highest('HIGHEST', '높은 평점'),
  lowest('LOWEST', '낮은 평점');

  const ReviewSort(this.apiName, this.label);
  final String apiName;
  final String label;
}

/// 리뷰 사진. 수정할 때 남길 사진은 [key]를 다시 보낸다.
class ReviewPhoto {
  ReviewPhoto.fromJson(Map json) : key = json['key'] as String, url = json['url'] as String;

  final String key;

  /// 로그인 없이 받는 사진 주소.
  final String url;
}

/// 코스 평점 요약(B8 · G2 상단). 리뷰가 없으면 평균은 모두 null이다.
class ReviewSummary {
  ReviewSummary.fromJson(Map json)
    : reviewCount = json['reviewCount'] as int,
      averageRating = (json['averageRating'] as num?)?.toDouble(),
      ratingCounts = [
        for (final star in const ['five', 'four', 'three', 'two', 'one']) (json['ratingCounts'] as Map)[star] as int,
      ],
      safety = _average(json, 'safety'),
      road = _average(json, 'road'),
      lighting = _average(json, 'lighting'),
      amenity = _average(json, 'amenity');

  final int reviewCount;

  /// 소수 첫째 자리까지(서버가 반올림).
  final double? averageRating;

  /// 별 5개부터 1개까지의 리뷰 수.
  final List<int> ratingCounts;

  /// 항목별 평균: 안전성 · 도로 상태 · 야간 조명 · 편의시설.
  final double? safety;
  final double? road;
  final double? lighting;
  final double? amenity;

  static double? _average(Map json, String item) => ((json['itemAverages'] as Map)[item] as num?)?.toDouble();
}

/// 리뷰 카드 한 장(B8-04 · G2). 내 리뷰(G2 상단 · B10 초기값)도 같은 모양이다.
class ReviewCard {
  ReviewCard.fromJson(Map json)
    : reviewId = json['reviewId'] as String,
      memberId = json['memberId'] as String,
      nickname = json['nickname'] as String?,
      profileImageUrl = json['profileImageUrl'] as String?,
      mine = json['mine'] as bool,
      rating = json['rating'] as int,
      safetyRating = json['safetyRating'] as int,
      roadRating = json['roadRating'] as int,
      lightingRating = json['lightingRating'] as int,
      amenityRating = json['amenityRating'] as int,
      content = json['content'] as String?,
      tags = [for (final tag in json['tags'] as List) ?ReviewTag.fromApi(tag as String)],
      photos = [for (final photo in json['photos'] as List) ReviewPhoto.fromJson(photo as Map)],
      bestProgressPercent = json['bestProgressPercent'] as int,
      completedCount = json['completedCount'] as int,
      createdAt = DateTime.parse(json['createdAt'] as String);

  final String reviewId;
  final String memberId;

  /// 회원 정보를 못 가져오면 null. 카드는 그대로 보인다.
  final String? nickname;
  final String? profileImageUrl;

  /// 요청자 본인 리뷰.
  final bool mine;
  final int rating;
  final int safetyRating;
  final int roadRating;
  final int lightingRating;
  final int amenityRating;

  /// 한줄 후기. 없으면 null.
  final String? content;
  final List<ReviewTag> tags;
  final List<ReviewPhoto> photos;

  /// 이 회원의 이 코스 최고 진행도(%). 리뷰를 쓰거나 고칠 때 저장된 값이다.
  final int bestProgressPercent;

  /// 이 회원의 이 코스 완주 횟수. 0이면 표시하지 않는다(정책 D-09).
  final int completedCount;

  /// 작성 시각. 수정해도 바뀌지 않는다.
  final DateTime createdAt;
}

/// 이 코스를 달린 내 기록 한 건. B2 · B10 상단에 "5.2km · 2026.09.08 완주 100% · 27:14"로 보인다.
class CourseRun {
  CourseRun.fromJson(Map json)
    : runRecordId = json['runRecordId'] as String,
      courseDistanceMeters = json['courseDistanceMeters'] as int,
      courseElapsedSeconds = json['courseElapsedSeconds'] as int,
      progressPercent = json['progressPercent'] as int,
      completed = json['completed'] as bool,
      endedAt = DateTime.parse(json['endedAt'] as String);

  final String runRecordId;
  final int courseDistanceMeters;
  final int courseElapsedSeconds;
  final int progressPercent;

  /// 서버 완주 판정. 완주하지 않았어도 리뷰 자격이 있을 수 있다.
  final bool completed;
  final DateTime endedAt;
}

/// 이 코스에 대한 내 리뷰 상태(G2 내 리뷰 · B2 · B10 진입).
///
/// [review]가 있으면 수정(B10, [sourceRecordDeleted]면 B10-1), 없고 [eligibleRecord]가 있으면 작성(B2),
/// 둘 다 없으면 아직 리뷰 자격이 없다.
class MyReview {
  MyReview.fromJson(Map json)
    : review = json['review'] == null ? null : ReviewCard.fromJson(json['review'] as Map),
      sourceRecord = json['sourceRecord'] == null ? null : CourseRun.fromJson(json['sourceRecord'] as Map),
      sourceRecordDeleted = json['sourceRecordDeleted'] as bool,
      eligibleRecord = json['eligibleRecord'] == null ? null : CourseRun.fromJson(json['eligibleRecord'] as Map);

  final ReviewCard? review;

  /// 내 리뷰의 근거 기록. 삭제됐으면 null.
  final CourseRun? sourceRecord;
  final bool sourceRecordDeleted;

  /// 리뷰를 쓸 수 있는 내 기록 중 가장 최근 것. 작성 요청의 근거 기록으로 보낸다.
  final CourseRun? eligibleRecord;
}

/// 사용자가 입력하는 리뷰 내용(B2 작성 · B10 수정 공통). 별점 5개는 모두 1~5 필수다.
class ReviewInput {
  const ReviewInput({
    required this.rating,
    required this.safetyRating,
    required this.roadRating,
    required this.lightingRating,
    required this.amenityRating,
    required this.content,
    required this.tags,
    required this.photoKeys,
  });

  final int rating;
  final int safetyRating;
  final int roadRating;
  final int lightingRating;
  final int amenityRating;

  /// 한줄 후기(200자까지). 비우면 없는 것으로 저장된다.
  final String content;
  final Set<ReviewTag> tags;

  /// 보이는 순서대로. 수정하면 이 목록으로 통째로 바뀐다(빠진 사진은 서버가 지운다).
  final List<String> photoKeys;

  Map<String, Object?> toJson() => {
    'rating': rating,
    'safetyRating': safetyRating,
    'roadRating': roadRating,
    'lightingRating': lightingRating,
    'amenityRating': amenityRating,
    'content': content,
    'tags': [for (final tag in tags) tag.apiName],
    'photoKeys': photoKeys,
  };
}

/// 커서로 이어 받은 리뷰 한 묶음.
typedef ReviewPage = ({List<ReviewCard> cards, String? nextCursor});

/// 리뷰 API(`/api/v1/reviews`). 모두 로그인이 필요하다.
class ReviewApiClient {
  ReviewApiClient(this._dio);

  final Dio _dio;
  static const _base = '/api/v1/reviews';

  /// 리뷰가 없거나 숨김 · 삭제된 코스면 리뷰 수 0이다.
  Future<ReviewSummary> summary(String courseId) async => ReviewSummary.fromJson(
    await callApi(() => _dio.get('$_base/summary', queryParameters: {'courseId': courseId})) as Map,
  );

  /// [cursor]가 null이면 첫 페이지. [excludeMine]이면 내 리뷰를 뺀다(G2 "다른 러너 리뷰").
  Future<ReviewPage> list(
    String courseId, {
    ReviewSort sort = ReviewSort.latest,
    bool photoOnly = false,
    bool excludeMine = false,
    String? cursor,
  }) async {
    final data = await callApi(
      () => _dio.get(
        _base,
        queryParameters: {
          'courseId': courseId,
          'sort': sort.apiName,
          'photoOnly': photoOnly,
          'excludeMine': excludeMine,
          'cursor': ?cursor,
        },
      ),
    ) as Map;
    return (
      cards: [for (final card in data['content'] as List) ReviewCard.fromJson(card as Map)],
      nextCursor: data['nextCursor'] as String?,
    );
  }

  Future<MyReview> mine(String courseId) async =>
      MyReview.fromJson(await callApi(() => _dio.get('$_base/me', queryParameters: {'courseId': courseId})) as Map);

  /// 코스별 평균 별점(지도 핀, 최대 100개). 리뷰가 없거나 숨김 · 삭제된 코스는 null이다.
  Future<Map<String, double?>> ratings(Iterable<String> courseIds) async {
    final data =
        await callApi(() => _dio.get('$_base/ratings', queryParameters: {'courseIds': courseIds.join(',')})) as List;
    return {
      for (final rating in data.cast<Map>())
        rating['courseId'] as String: (rating['averageRating'] as num?)?.toDouble(),
    };
  }

  /// 자격 없음 REVIEW-001, 이미 작성 002, 숨김 · 삭제 코스 005, 사진 006 · 007.
  Future<void> write(String courseId, String sourceRunRecordId, ReviewInput input) => callApi(
    () => _dio.post(_base, data: {'courseId': courseId, 'sourceRunRecordId': sourceRunRecordId, ...input.toJson()}),
  );

  /// 전체 교체. 없음 REVIEW-003, 내 리뷰 아님 004, 숨김 · 삭제 코스 005, 사진 006 · 007.
  Future<void> edit(String reviewId, ReviewInput input) =>
      callApi(() => _dio.put('$_base/${Uri.encodeComponent(reviewId)}', data: input.toJson()));

  /// 사진도 함께 지운다.
  Future<void> delete(String reviewId) => callApi(() => _dio.delete('$_base/${Uri.encodeComponent(reviewId)}'));

  /// 리뷰 사진 한 장을 올릴 폼. 사진 업로더(`PhotoUploader.upload`)에 넘긴다.
  Future<UploadForm> photoUploadForm() async =>
      UploadForm.fromJson(await callApi(() => _dio.post('$_base/photo-uploads')) as Map);
}

final reviewApiClientProvider = Provider<ReviewApiClient>((ref) => ReviewApiClient(ref.watch(dioProvider)));
