package com.wadadak.run;

import com.wadadak.common.geo.GeoPoint;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class RunContracts {
    private RunContracts() {}
    public enum Kind { START, GPS, PAUSE, RESUME, GAP, END, CADENCE }
    public record Prepare(@NotNull Instant startedAt, @Pattern(regexp="FREE") String mode) {}
    public record Input(@Min(0) long seq, @NotNull Kind kind, @Min(0) long elapsedMs,
                        @NotNull Instant measuredAt, GeoPoint location, Double accuracyM,
                        @Size(max=40) String reason, Double speedMps, Double speedAccuracyMps, Integer steps, Long durationMs, Long sampleEndMs,
                        Double altitudeM, Double altitudeAccuracyM) {
        // Existing sources and stored GPS payloads remain valid without altitude.
        public Input(long seq, Kind kind, long elapsedMs, Instant measuredAt, GeoPoint location, Double accuracyM, String reason, Double speedMps, Double speedAccuracyMps, Integer steps, Long durationMs, Long sampleEndMs) {
            this(seq,kind,elapsedMs,measuredAt,location,accuracyM,reason,speedMps,speedAccuracyMps,steps,durationMs,sampleEndMs,null,null);
        }
        public Input(long seq, Kind kind, long elapsedMs, Instant measuredAt, GeoPoint location, Double accuracyM, String reason, Double speedMps, Double speedAccuracyMps) {
            this(seq,kind,elapsedMs,measuredAt,location,accuracyM,reason,speedMps,speedAccuracyMps,null,null,null);
        }
        public Input(long seq, Kind kind, long elapsedMs, Instant measuredAt,
                     GeoPoint location, Double accuracyM, String reason) {
            this(seq, kind, elapsedMs, measuredAt, location, accuracyM, reason, null, null, null, null, null);
        }
    }
    public record Upload(@Min(1) @Max(1000000) long finalSeq,
                         @NotEmpty @Size(max=500) List<@NotNull @Valid Input> inputs) {}
    public record Range(long fromSeq, long toSeq) {}
    public record Status(UUID sessionId, String processing, List<Range> missingRanges,
                         UUID recordId, String failure) {}
    public record Metrics(double distanceM, long elapsedMs, long activeMs,
                          int gapCount, Double paceSecondsPerKm, long movingMs,
                          Double elapsedPaceSecondsPerKm, Double averageCadence, long cadenceCoverageMs, long steps) {
        public Metrics(double distanceM, long elapsedMs, long activeMs, int gapCount, Double paceSecondsPerKm, long movingMs, Double elapsedPaceSecondsPerKm) {
            this(distanceM,elapsedMs,activeMs,gapCount,paceSecondsPerKm,movingMs,elapsedPaceSecondsPerKm,null,0,0);
        }
        public Metrics(double distanceM, long elapsedMs, long activeMs, int gapCount, Double paceSecondsPerKm) {
            this(distanceM, elapsedMs, activeMs, gapCount, paceSecondsPerKm, activeMs,
                distanceM > 0 ? elapsedMs / distanceM : null, null, 0, 0);
        }
    }
    public record Result(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt,
                         String endReason, Metrics metrics, List<List<GeoPoint>> routeSegments, List<Lap> laps,
                         String policyVersion, String calculationVersion, ResultStats stats) {
        public Result(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason,
                      Metrics metrics, List<List<GeoPoint>> routeSegments, List<Lap> laps, String policyVersion, String calculationVersion) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,routeSegments,laps,policyVersion,calculationVersion,null);
        }
        public Result(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason,
                      Metrics metrics, List<List<GeoPoint>> routeSegments, List<Lap> laps) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,routeSegments,laps,null,null);
        }
        public Result { laps = laps == null ? List.of() : List.copyOf(laps); }
        public Result(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason, Metrics metrics, List<List<GeoPoint>> routeSegments) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,routeSegments,List.of());
        }
    }
    public record ResultStats(String version, Double elevationGainM, boolean elevationPartial,
                              Integer bestLapNumber, Double bestLapPaceSecondsPerKm, Double bestPaceSecondsPerKm) {}
    public record Lap(int number, double distanceM, long movingMs, long elapsedMs, boolean complete, Double paceSecondsPerKm) {}
    public record Deleted(UUID id, boolean deleted) {}
    public record RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt,
                                String endReason, Metrics metrics, ResultStats stats) {
        public RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason, Metrics metrics) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,null);
        }
        public static RecordSummary from(Result result) {
            return new RecordSummary(result.id(),result.startedAt(),result.endedAt(),result.registeredAt(),result.endReason(),result.metrics(),result.stats());
        }
    }
}
