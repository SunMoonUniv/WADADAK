package com.wadadak.event.member;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 회원 탈퇴. 키: memberId.
 */
public record MemberWithdrawnEvent(UUID eventId, Instant occurredAt, UUID memberId, Instant withdrawnAt)
        implements IntegrationEvent {
}
