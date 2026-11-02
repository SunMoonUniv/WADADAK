package com.wadadak.event.run;

import com.wadadak.event.IntegrationEvent;
import java.time.Instant;
import java.util.UUID;

/** One original record's course performance, never another personal run or course challenge. Key: runRecordId. */
public record GpsSourceLinkedEvent(UUID eventId, Instant occurredAt, UUID runRecordId, UUID memberId,
        UUID courseId, int courseElapsedSeconds, int courseDistanceMeters,
        Double recognizedDistanceMeters, Double progress, boolean reviewEligible,
        Instant completedAt, Instant startedAt, Instant endedAt, Instant registeredAt,
        String policyVersion) implements IntegrationEvent {}
