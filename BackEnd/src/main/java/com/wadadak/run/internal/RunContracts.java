package com.wadadak.run.internal;

import com.wadadak.common.geo.GeoPoint;
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
                                 int totalDistanceMeters, long version) {}
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
    public record Result(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt,
                         String endReason, Metrics metrics, List<List<GeoPoint>> routeSegments, List<Lap> laps,
                         String policyVersion, String calculationVersion, ResultStats stats, CourseOutcome course) {
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
    /** 기록 목록 한 줄의 코스 요약(MY I1 카드 제목·완주·진행도·리뷰 쓰기·코스 상세). 자유 러닝이면 목록의 {@code course}가 null */
    public record CourseSummary(UUID courseId, String courseName, boolean completed, double progressPercent, boolean reviewEligible) {
        public static CourseSummary from(CourseOutcome course) {
            return course == null ? null : new CourseSummary(course.courseId(), course.courseName(), course.completed(),
                    course.progressPercent(), course.reviewEligible());
        }
    }
    public record RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt,
                                String endReason, Metrics metrics, ResultStats stats, CourseSummary course) {
        public RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason, Metrics metrics, ResultStats stats) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,stats,null);
        }
        public RecordSummary(UUID id, Instant startedAt, Instant endedAt, Instant registeredAt, String endReason, Metrics metrics) {
            this(id,startedAt,endedAt,registeredAt,endReason,metrics,null);
        }
        public static RecordSummary from(Result result) {
            return new RecordSummary(result.id(),result.startedAt(),result.endedAt(),result.registeredAt(),result.endReason(),result.metrics(),result.stats(),
                    CourseSummary.from(result.course()));
        }
    }
}
