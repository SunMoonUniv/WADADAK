package com.wadadak.run.internal.recording;

import com.wadadak.run.internal.RunContracts.GhostOutcome;
import java.util.List;
import java.util.UUID;

/** Owner-only derived comparison; never exposes raw GPS or public opponents' private sensors. */
record GhostComparison(String version, UUID sessionId, UUID sourceRecordId, GhostOutcome result,
        String status, UUID courseId, String courseName, int distanceMeters, String sourceKind,
        String publicPeriod, String sourceState, double reachedMeters, String personalBest, Long previousBestSeconds,
        ComparisonMetrics ours, ComparisonMetrics ghost, List<ComparisonSegment> segments) {
    GhostComparison withSourceState(String state) {
        return new GhostComparison(version,sessionId,sourceRecordId,result,status,courseId,courseName,
                distanceMeters,sourceKind,publicPeriod,state,reachedMeters,personalBest,previousBestSeconds,ours,ghost,segments);
    }
}
record ComparisonMetrics(Long elapsedSeconds, Long activeMs, Double paceSecondsPerKm,
                         Double averageCadence, Integer bestSegment) {}
record ComparisonSegment(int number, double fromMeters, double toMeters, boolean fullKilometer,
        Long ourSeconds, Long ghostSeconds, Long deltaSeconds, Long cumulativeDeltaSeconds, String unavailableReason, Long ourMs, Long ghostMs, Long deltaMs, Long cumulativeDeltaMs) {}
