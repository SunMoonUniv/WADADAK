package com.wadadak.event.course;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 코스 공개 상태 변경(상태형). 키: courseId. 수신 측은 저장된 version보다 큰 값만 반영한다.
 * {@code HIDDEN}이면 노출 중지, {@code DELETED}면 그 코스의 랭킹 엔트리·리뷰·리뷰 자격을 삭제한다(개발 정책 5.6).
 *
 * @param status  {@code HIDDEN} 또는 {@code DELETED}. 상태는 되돌아가지 않으므로 {@code ACTIVE}로 발행하지 않는다
 * @param version 코스 엔티티의 {@code @Version}
 */
public record CourseStatusChangedEvent(UUID eventId, Instant occurredAt, UUID courseId, CourseStatus status,
                                       CourseStatusReason reason, long version)
        implements IntegrationEvent {
}
