package com.wadadak.event;

import java.time.Instant;
import java.util.UUID;

/**
 * 모든 모듈 간 이벤트의 공통 필드. {@code eventId}는 발행 시 생성하고 수신 측 멱등 키로 쓴다.
 */
public interface IntegrationEvent {

    UUID eventId();

    Instant occurredAt();
}
