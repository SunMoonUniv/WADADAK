package com.wadadak.course.internal.course;

import java.time.Instant;
import java.util.UUID;

/** 만료 임박 알림에 실을 코스 값 */
public record ExpiringCourse(UUID id, UUID creatorId, String name, Instant expiresAt) {
}
