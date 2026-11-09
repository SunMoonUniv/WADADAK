package com.wadadak.event.run;

import com.wadadak.event.IntegrationEvent;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Completed course run's GPS track from measurement start to completedAt (later running is cut off). Key: runRecordId.
 * Same shape as course-source: segments split at GPS gaps, each point with accuracy and altitude.
 * course builds the elevation profile of courses that have none (first completion with enough altitude).
 */
public record CourseRunTrackEvent(UUID eventId, Instant occurredAt, UUID runRecordId, UUID courseId,
        List<List<TrackPoint>> segments) implements IntegrationEvent {

    public record TrackPoint(double lat, double lng, Double accuracyM, Double altitudeM, Double altitudeAccuracyM) {}
}
