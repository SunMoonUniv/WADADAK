package com.wadadak.event.run;

import com.wadadak.event.IntegrationEvent;
import java.time.Instant;
import java.util.UUID;

/** Registered record. Key: runRecordId; free runs have no courseId. */
public record RunSessionEndedEvent(UUID eventId, Instant occurredAt,
        UUID runRecordId, UUID memberId, UUID courseId, boolean completed,
        double distanceMeters, int courseElapsedSeconds, int courseDistanceMeters,
        double recognizedDistanceMeters, double progress, boolean reviewEligible,
        Instant completedAt, Instant startedAt, Instant endedAt, Instant registeredAt,
        String policyVersion) implements IntegrationEvent {}
