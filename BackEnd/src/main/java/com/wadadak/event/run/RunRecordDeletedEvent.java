package com.wadadak.event.run;

import com.wadadak.event.IntegrationEvent;
import java.time.Instant;
import java.util.UUID;

/** Deleted registered record. Contains the values needed to undo its aggregates. */
public record RunRecordDeletedEvent(UUID eventId, Instant occurredAt,
        UUID runRecordId, UUID memberId, UUID courseId, boolean completed,
        double distanceMeters, int courseElapsedSeconds, Instant startedAt,
        Instant endedAt, Instant registeredAt) implements IntegrationEvent {}
