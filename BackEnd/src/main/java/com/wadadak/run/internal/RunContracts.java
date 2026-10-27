package com.wadadak.run.internal;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.GpsGapCheck;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class RunContracts {
    private RunContracts() {}
    public enum Kind { START, GPS, PAUSE, RESUME, GAP, SEGMENT_END, END, CADENCE, BAROMETER }
    /** 종료 후 업로드 준비. 코스 러닝인지는 서버의 코스 시도로 정한다(mode는 FREE·COURSE 아무거나, 시작 신호 세션은 같은 startedAt) */
    public record Prepare(@NotNull Instant startedAt, @Pattern(regexp="FREE|COURSE") String mode) {}
    /** 코스 러닝 준비(C6, 측정 시작 전). 서버가 코스 활성 여부를 확인하고 판정용 경로를 저장한다(정책 D-08) */
    public record CoursePrepare(@NotNull UUID courseId) {}
    /** 코스 러닝 시작 신호(카운트다운 끝, 측정 시작). 같은 startedAt 재시도는 한 번만 반영한다 */
    public record CourseStart(@NotNull Instant startedAt) {}
    /** 코스 러닝 준비 응답. 앱은 이 경로로 안내하고 기기에 저장한다 */
    public record CourseSnapshot(UUID sessionId, UUID courseId, String name, List<GeoPoint> route,
                                 int totalDistanceMeters, long version, List<Integer> breaks) {
        public CourseSnapshot { breaks = breaks == null ? List.of() : List.copyOf(breaks); }
        public CourseSnapshot(UUID sessionId, UUID courseId, String name, List<GeoPoint> route, int totalDistanceMeters, long version) {
            this(sessionId,courseId,name,route,totalDistanceMeters,version,List.of());
        }
    }
    /**
     * 서버 코스 판정 결과(정책 제3부 5.1·5.3). 코스 러닝 기록에만 있다.
     *
     * @param courseName           달릴 때의 코스 이름(준비 때 스냅샷). 이후 코스 이름이 바뀌어도 기록에는 이 이름을 보인다
     * @param courseDistanceMeters 코스 전체 거리(코스 등록 값). 랭킹 페이스 계산에 쓴다
     * @param reason               COMPLETED · START_NOT_CONFIRMED · FINISH_NOT_REACHED · DISTANCE_SHORT
     * @param progressPercent      진행도 0~100
     * @param completedAt          미완주면 null
     */
    public record CourseOutcome(UUID courseId, String courseName, long courseVersion, int courseDistanceMeters, boolean completed,
                                String reason, double recognizedDistanceMeters, double progressPercent, Instant completedAt,
                                long courseElapsedSeconds, long courseMovingSeconds, boolean reviewEligible) {}
    public record Input(@Min(0) long seq, @NotNull Kind kind, @Min(0) long elapsedMs,
                        @NotNull Instant measuredAt, GeoPoint location, Double accuracyM,
                        @Size(max=40) String reason, Double speedMps, Double speedAccuracyMps, Integer steps, Long durationMs, Long sampleEndMs,
                        Double altitudeM, Double altitudeAccuracyM, Double pressureHpa, Integer pressureAccuracy) {
        public Input(long seq, Kind kind, long elapsedMs, Instant measuredAt, GeoPoint location, Double accuracyM, String reason, Double speedMps, Double speedAccuracyMps, Integer steps, Long durationMs, Long sampleEndMs, Double altitudeM, Double altitudeAccuracyM) {
            this(seq,kind,elapsedMs,measuredAt,location,accuracyM,reason,speedMps,speedAccuracyMps,steps,durationMs,sampleEndMs,altitudeM,altitudeAccuracyM,null,null);
        }
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
    /** @param gpsGap GPS 코스 등록 끊긴 구간 판단(CourseApi.checkGpsGaps, F7 B6·결과 화면 "GPS 정확도 부족"). 처리 뒤 쓰기 트랜잭션 밖에서 채운다. 아직이면 null */
    public record Result(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt,
                         String endReason, Metrics metrics, List<List<GeoPoint>> routeSegments, List<Lap> laps,
                         String policyVersion, String calculationVersion, ResultStats stats, CourseOutcome course, GpsGapCheck gpsGap, GhostOutcome ghost) {
        public Result(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason,
                      Metrics metrics, List<List<GeoPoint>> routeSegments, List<Lap> laps, String policyVersion,
                      String calculationVersion, ResultStats stats, CourseOutcome course, GpsGapCheck gpsGap) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,routeSegments,laps,policyVersion,calculationVersion,stats,course,gpsGap,null);
        }
        public Result(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason,
                      Metrics metrics, List<List<GeoPoint>> routeSegments, List<Lap> laps, String policyVersion, String calculationVersion, ResultStats stats, CourseOutcome course) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,routeSegments,laps,policyVersion,calculationVersion,stats,course,null,null);
        }
        public Result withGpsGap(GpsGapCheck value) {
            return new Result(id,startedAt,endedAt,registeredAt,endReason,metrics,routeSegments,laps,policyVersion,calculationVersion,stats,course,value,ghost);
        }
        /** 자유 러닝 결과: 코스 판정 없음 */
        public Result(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason,
                      Metrics metrics, List<List<GeoPoint>> routeSegments, List<Lap> laps, String policyVersion, String calculationVersion, ResultStats stats) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,routeSegments,laps,policyVersion,calculationVersion,stats,null);
        }
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
                              Integer bestLapNumber, Double bestLapPaceSecondsPerKm, Double bestPaceSecondsPerKm, String elevationSource) {
        public ResultStats(String version, Double elevationGainM, boolean elevationPartial, Integer bestLapNumber, Double bestLapPaceSecondsPerKm, Double bestPaceSecondsPerKm) {
            this(version,elevationGainM,elevationPartial,bestLapNumber,bestLapPaceSecondsPerKm,bestPaceSecondsPerKm,null);
        }
    }
    public record Lap(int number, double distanceM, long movingMs, long elapsedMs, boolean complete, Double paceSecondsPerKm) {}
    public record Deleted(UUID id, boolean deleted) {}
    /**
     * GPS 코스 등록(F7 B6·D4)용 원본 경로. 등록 가능 여부는 course가 판단한다.
     *
     * @param distanceMeters 결과 화면과 같은 기록 거리
     * @param segments       결과 화면 지도와 같은 인정 이동 경로. 일시정지·GPS 공백·튐에서 끊긴 구간을 순서대로 담고 구간 사이는 잇지 않는다
     */
    public record CourseSource(UUID recordId, double distanceMeters, List<List<SourcePoint>> segments) {}
    /** 지점별 GPS 원본 값. 정확도·고도는 없으면 null */
    public record SourcePoint(double lat, double lng, Double accuracyM, Double altitudeM, Double altitudeAccuracyM) {}
    /** Owner-only derived playback. Does not modify the source result or publish events. */
    public enum GhostSpanState { TRACKED, PAUSED, UNKNOWN }
    public enum OwnGhostSort { BEST, RECENT }
    public enum OwnGhostPeriod { ALL, MONTH, WEEK }
    /** Lightweight own completion only; replay eligibility is checked on selection. */
    public record OwnGhostCandidate(UUID id, UUID courseId, long courseVersion, Instant startedAt,
                                    Instant completedAt, Instant registeredAt,
                                    long courseElapsedSeconds, int courseDistanceMeters, Double averageCadence) {}
    public record OwnGhostSummary(long count, Double averageSeconds, OwnGhostCandidate best) {}
    public record OwnGhostCandidatePage(List<OwnGhostCandidate> content, String nextCursor, OwnGhostSummary summary) {}
    public record GhostSample(long elapsedMs, Double coursePositionM) {}
    public record GhostSpan(long fromMs, long toMs, Double fromPositionM, Double toPositionM, GhostSpanState state) {}
    public record GhostQuality(long activeDurationMs, long gapMs, long maxGapMs) {}
    public record GhostPlayback(UUID sourceRecordId, CourseSnapshot course, String version,
                                String sourcePolicyVersion, String sourceCalculationVersion,
                                long courseElapsedSeconds, Long durationMs, boolean eligible,
                                List<String> unavailableReasons, GhostQuality quality,
                                List<GhostSample> samples, List<GhostSpan> spans) {}
    /** After course preparation, approve one own opponent. Reuse every field when retrying. */
    public record GhostStart(UUID courseId, @Min(0) Long courseVersion,
                             @NotNull UUID sourceRecordId, @NotNull Instant startedAt,
                             @NotNull @Pattern(regexp="GHOST_PLAYBACK_V1|GHOST_PLAYBACK_FREE_V1") String playbackVersion,
                             @Size(max=64) String referenceHash) {
        public GhostStart(UUID courseId, Long courseVersion, UUID sourceRecordId, Instant startedAt, String playbackVersion) {
            this(courseId,courseVersion,sourceRecordId,startedAt,playbackVersion,null);
        }
    }
    public record FreeGhostCandidate(UUID id, Instant startedAt, Instant registeredAt, String endReason,
                                     double distanceM, long elapsedMs, boolean distanceEligible) {}
    public record FreeGhostPage(List<FreeGhostCandidate> content, String nextCursor) {}
    public record FreeGhostPreparation(GhostPlayback playback, double originalDistanceM,
                                       long originalElapsedMs, String endReason, String referenceHash) {}
    /** Durable approval receipt, not the live running state or a completion verdict. */
    public record GhostStartApproval(String version, UUID sessionId, UUID sourceRecordId,
                                     Instant startedAt, Instant approvedAt, Instant courseValidatedAt,
                                     CourseSnapshot course, GhostPlayback playback) {}
    public enum GhostVerdict { WIN, LOSE, DRAW, INVALID }
    public enum GhostVerdictReason { COMPLETED_TIME_COMPARISON, VOLUNTARY_BEFORE_GHOST_FINISH,
        VOLUNTARY_AFTER_GHOST_FINISH, INVOLUNTARY_INCOMPLETE, FINISH_NOT_CONFIRMED }
    /** Immutable server summary. Replay is preserved for the duel and subsequent result comparison. */
    public record GhostOutcome(String version, UUID sessionId, UUID sourceRecordId, GhostVerdict outcome, GhostVerdictReason reason,
                                boolean completed, long courseElapsedSeconds, long sourceElapsedSeconds,
                                long courseEndElapsedMs, long sourceDurationMs, String courseEndReason,
                                Instant finalizedAt) {}
    /** 기록 목록 한 줄의 코스 요약(MY I1 카드 제목·완주·진행도·리뷰 쓰기·코스 상세). 자유 러닝이면 목록의 {@code course}가 null */
    public record CourseSummary(UUID courseId, String courseName, boolean completed, double progressPercent, boolean reviewEligible) {
        public static CourseSummary from(CourseOutcome course) {
            return course == null ? null : new CourseSummary(course.courseId(), course.courseName(), course.completed(),
                    course.progressPercent(), course.reviewEligible());
        }
    }
    public record RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt,
                                String endReason, Metrics metrics, ResultStats stats, CourseSummary course, GpsGapCheck gpsGap, GhostOutcome ghost) {
        public RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason,
                             Metrics metrics, ResultStats stats, CourseSummary course, GpsGapCheck gpsGap) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,stats,course,gpsGap,null);
        }
        public RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason, Metrics metrics, ResultStats stats, CourseSummary course) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,stats,course,null,null);
        }
        public RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason, Metrics metrics, ResultStats stats) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,stats,null);
        }
        public RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason, Metrics metrics) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,null);
        }
        public static RecordSummary from(Result result) {
            return new RecordSummary(result.id(),result.startedAt(),result.endedAt(),result.registeredAt(),result.endReason(),result.metrics(),result.stats(),
                    CourseSummary.from(result.course()),result.gpsGap(),result.ghost());
        }
    }
}
