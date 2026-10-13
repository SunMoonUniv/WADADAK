package com.wadadak.event.review;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 리뷰 삭제(집계형). 키: courseId. 수신 측(course)은 평점 합계에서 rating을 빼고 리뷰 수를 1 줄인다.
 * 작성자 삭제와 회원 탈퇴로 지울 때 발행한다. 코스가 {@code DELETED}가 되어 함께 지울 때는 course가 그 코스의 통계를
 * 직접 지우므로 발행하지 않는다(개발 정책 5.6).
 *
 * @param rating    삭제된 리뷰의 마지막 전체 별점
 * @param createdAt 리뷰 작성 시각. course 일별 통계는 작성일에서 뺀다
 */
public record ReviewDeletedEvent(UUID eventId, Instant occurredAt, UUID reviewId, UUID courseId, int rating,
                                 Instant createdAt)
        implements IntegrationEvent {
}
