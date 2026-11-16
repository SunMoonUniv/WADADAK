package com.wadadak.event.member;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 내 정보 공개 설정 변경(상태형). 키: memberId. 수신 측은 저장된 version보다 큰 값만 반영한다.
 */
public record MemberVisibilityChangedEvent(UUID eventId, Instant occurredAt, UUID memberId, boolean visible, long version)
        implements IntegrationEvent {
}
