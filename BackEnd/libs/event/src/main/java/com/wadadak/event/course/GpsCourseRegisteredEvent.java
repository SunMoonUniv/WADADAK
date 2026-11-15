package com.wadadak.event.course;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.event.IntegrationEvent;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Versioned registration evidence. Source segments precede joining/simplification; no run callback is needed. */
public record GpsCourseRegisteredEvent(UUID eventId, Instant occurredAt, UUID courseId, UUID creatorId,
        UUID sourceRunRecordId, String courseName, List<GeoPoint> route, int distanceMeters,
        long courseVersion, CourseStatus status, List<List<GeoPoint>> sourceSegments) implements IntegrationEvent {
    public GpsCourseRegisteredEvent {
        route = List.copyOf(route);
        sourceSegments = sourceSegments.stream().map(List::copyOf).toList();
    }
}
