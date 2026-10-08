package com.wadadak.event.course;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 코스 등록. 키: courseId.
 *
 * @param sourceRunRecordId GPS 기록으로 등록했으면 원본 러닝 기록 ID, 직접 등록이면 {@code null}
 */
public record CourseCreatedEvent(UUID eventId, Instant occurredAt, UUID courseId, UUID creatorId, UUID sourceRunRecordId)
        implements IntegrationEvent {
}
