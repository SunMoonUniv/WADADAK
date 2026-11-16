package com.wadadak.event.run;

import com.wadadak.event.IntegrationEvent;
import java.time.Instant;
import java.util.UUID;

/** Carries the original immutable contribution so removal is safe even when it arrives before creation. */
public record GpsSourceUnlinkedEvent(UUID eventId, Instant occurredAt, GpsSourceLinkedEvent source,
        String reason) implements IntegrationEvent {}
