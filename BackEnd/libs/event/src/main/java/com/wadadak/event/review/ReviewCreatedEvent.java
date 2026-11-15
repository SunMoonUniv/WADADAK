package com.wadadak.event.review;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 리뷰 작성(집계형). 키: courseId. 수신 측(course)은 평점 합계에 rating을 더하고 리뷰 수를 1 늘린다.
 *
 * @param rating    전체 별점 1~5
 * @param createdAt 리뷰 작성 시각. course 일별 통계는 이 날짜에 반영한다(개발 정책 5.6 기간 정렬)
 */
public record ReviewCreatedEvent(UUID eventId, Instant occurredAt, UUID reviewId, UUID courseId, int rating,
                                 Instant createdAt)
        implements IntegrationEvent {
}
