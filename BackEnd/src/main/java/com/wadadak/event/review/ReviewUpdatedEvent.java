package com.wadadak.event.review;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 리뷰 수정(집계형). 키: courseId. 수신 측(course)은 평점 합계에 (newRating − oldRating)을 더한다. 리뷰 수는 그대로다.
 * 전체 별점이 바뀌지 않은 수정(내용·사진·항목 평가만 수정)은 발행하지 않는다.
 *
 * @param createdAt 리뷰 작성 시각(수정 시각이 아니다). course 일별 통계는 작성일에 반영한다
 */
public record ReviewUpdatedEvent(UUID eventId, Instant occurredAt, UUID reviewId, UUID courseId, int oldRating,
                                 int newRating, Instant createdAt)
        implements IntegrationEvent {
}
