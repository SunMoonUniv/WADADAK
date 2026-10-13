package com.wadadak.review.internal;

import java.time.Instant;
import java.util.Set;
import java.util.UUID;

/**
 * 작성·수정한 리뷰 응답.
 *
 * <p>엔티티({@link Review})를 그대로 JSON으로 내보내지 않고 응답 전용 record로 옮겨 담는다.
 * 엔티티를 바로 내보내면 DB 구조가 API에 묶이고, 숨겨야 할 값까지 나갈 수 있다(개발 정책 3.1 "엔티티 대신 DTO").
 *
 * @param content             한줄 후기. 없으면 {@code null}
 * @param bestProgressPercent 이 회원의 이 코스 최고 진행도(%). 리뷰 카드에 "완주 100%"·"62% 주행"처럼 표시한다
 * @param createdAt           작성 시각. 수정해도 바뀌지 않는다
 */
record ReviewView(UUID reviewId, UUID courseId, UUID sourceRunRecordId,
                  int rating, int safetyRating, int roadRating, int lightingRating, int amenityRating,
                  String content, Set<ReviewTag> tags, int bestProgressPercent, Instant createdAt, Instant updatedAt) {

    static ReviewView from(Review review) {
        return new ReviewView(review.getId(), review.getCourseId(), review.getSourceRunRecordId(),
                review.getRating(), review.getSafetyRating(), review.getRoadRating(), review.getLightingRating(),
                review.getAmenityRating(), review.getContent(), Set.copyOf(review.getTags()), review.getBestProgressPercent(),
                review.getCreatedAt(), review.getUpdatedAt());
    }
}
