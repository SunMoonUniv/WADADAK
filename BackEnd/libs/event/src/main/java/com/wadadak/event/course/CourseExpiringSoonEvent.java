package com.wadadak.event.course;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 코스 만료 임박. 키: courseId. 만료 배치가 매일 09:00(Asia/Seoul)에 D-7·D-1 코스마다 발행한다(정책 공통 4).
 * 수신 측은 같은 {@code (courseId, expiresAt, daysLeft)}를 한 번만 처리한다.
 *
 * @param courseName 알림 문구용. 발행 시점의 이름
 * @param expiresAt  만료 시각(만료일 23:59:59 Asia/Seoul)
 * @param daysLeft   7 또는 1
 */
public record CourseExpiringSoonEvent(UUID eventId, Instant occurredAt, UUID courseId, UUID creatorId, String courseName,
                                      Instant expiresAt, int daysLeft)
        implements IntegrationEvent {
}
