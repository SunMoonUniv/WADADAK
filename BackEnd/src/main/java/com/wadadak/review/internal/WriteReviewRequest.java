package com.wadadak.review.internal;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.Set;
import java.util.UUID;

/**
 * 리뷰 작성(B2) 요청 본문. 범위를 벗어나면 COMMON-001.
 *
 * <p>수정 요청({@link ReviewContent})에 어느 코스·어느 기록으로 쓰는지(courseId·sourceRunRecordId)만 더한 모양이다.
 * JSON이 평평한 한 덩어리로 오도록 필드를 그대로 나열하고, 서비스에는 {@link #toContent()}로 넘긴다.
 *
 * @param sourceRunRecordId 근거 기록. 이 코스에서 리뷰 자격을 얻은 내 기록이어야 한다(아니면 REVIEW-001)
 * @param rating            전체 별점 1~5. 항목 평가 4개도 모두 1~5 필수
 * @param content           한줄 후기. 선택, 200자까지
 * @param tags              선택. 없으면 빈 목록
 */
record WriteReviewRequest(
        @NotNull UUID courseId,
        @NotNull UUID sourceRunRecordId,
        @Min(1) @Max(5) int rating,
        @Min(1) @Max(5) int safetyRating,
        @Min(1) @Max(5) int roadRating,
        @Min(1) @Max(5) int lightingRating,
        @Min(1) @Max(5) int amenityRating,
        @Size(max = ReviewContent.MAX_CONTENT_LENGTH) String content,
        Set<@NotNull ReviewTag> tags) {

    ReviewContent toContent() {
        return new ReviewContent(rating, safetyRating, roadRating, lightingRating, amenityRating, content, tags);
    }
}
