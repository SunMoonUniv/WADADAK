package com.wadadak.run.internal.judging;

import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.RunContracts.Kind;
import com.wadadak.run.internal.judging.CourseTracker.Point;
import com.wadadak.run.internal.judging.RecognizedDistance.Progress;
import com.wadadak.run.internal.judging.RecognizedDistance.Range;

import java.time.Instant;
import java.util.List;
import java.util.Objects;

/**
 * 서버 코스 판정의 입구(정책 제3부 5.1·5.3). 경로 기하 → 윈도우 추적 → 인정 거리 → 완주·리뷰 자격·진행도·코스 시간.
 * 앱의 완주 안내와 상관없이 업로드된 입력만으로 판정한다.
 */
public final class CourseJudge {

    /** 완주 거리 조건: 인정 거리 ≥ 전체 × 0.95, 경계 포함(정책 5.3) */
    static final double COMPLETION_RATIO = 0.95;
    /** 리뷰 자격: 인정 거리 ≥ max(1,000m, 전체 × 0.2), 경계 포함(정책 5.1) */
    static final double REVIEW_MIN_M = 1000;
    static final double REVIEW_RATIO = 0.2;
    /**
     * 경계 비교 여유(m). 투영·합산의 부동소수 오차로 4,750이 4,749.9999…가 되어 경계에서 떨어지지 않게 한다.
     * 거리 95%·리뷰 자격·끝 도달·출발 반경, 경계를 포함하는 비교 모두에 쓴다
     */
    private static final double EPSILON_M = 1e-6;

    /** 판정 사유. 여러 개면 앞의 것 */
    public enum Reason { COMPLETED, START_NOT_CONFIRMED, FINISH_NOT_REACHED, DISTANCE_SHORT }

    /**
     * @param ranges               인정 범위(코스상 위치 m)
     * @param recognizedM          코스 인정 거리(m)
     * @param courseLengthM        코스 전체 길이(m). 판정 평면에서 잰 길이라 {@code totalDistanceMeters}와 약 0.2% 다를 수 있다
     * @param progressPercent      진행도 = 인정 거리 ÷ 전체 × 100, 최대 100
     * @param completedAt          완주 조건을 처음 함께 충족한 표본의 측정 시각. 미완주면 null
     * @param courseElapsedSeconds 코스 총 소요(정지 포함). 완주면 완주 시점까지, 아니면 구간 종료(SEGMENT_END, 없으면 END)까지
     * @param courseMovingSeconds  코스 달린 시간 = 총 소요 − 그 사이 일시정지
     */
    public record Judgement(List<Range> ranges, double recognizedM, double courseLengthM, double progressPercent,
                     boolean completed, Reason reason, Instant completedAt,
                     long courseElapsedSeconds, long courseMovingSeconds, boolean reviewEligible) {
    }

    /** F9 reads the existing projection; it does not introduce a second course matcher. */
    public record CourseSample(long seq, long elapsedMs, Double positionM, boolean connected, boolean ambiguous) {}
    public record Analysis(Judgement judgement, List<CourseSample> samples, long courseElapsedMs) {}

    private final JudgingConfig config;

    /** 주행 검증 전 개발용 기준값({@link JudgingConfig#DEFAULTS}) */
    public CourseJudge() {
        this(JudgingConfig.DEFAULTS);
    }

    CourseJudge(JudgingConfig config) {
        this.config = config;
    }

    public Judgement judge(CourseRouteSnapshot course, List<Input> inputs) {
        return analyze(course, inputs).judgement();
    }

    public Analysis analyze(CourseRouteSnapshot course, List<Input> inputs) {
        return analyze(course.route(),List.of(),inputs);
    }
    /** Run-owned reference geometry. Breaks have no inferred connecting segment or distance. */
    public Analysis analyze(List<com.wadadak.common.geo.GeoPoint> reference, List<Integer> breaks, List<Input> inputs) {
        RouteGeometry route = new RouteGeometry(reference,breaks);
        List<Point> points = new CourseTracker(route, config).track(inputs);
        RecognizedDistance recognized = RecognizedDistance.of(points);
        double length = route.length();

        boolean started = startConfirmed(points);
        double finishFrom = length - config.finishToleranceM() - EPSILON_M;
        Progress completion = started ? firstCompletion(recognized, finishFrom, length * COMPLETION_RATIO) : null;

        Reason reason;
        if (completion != null) {
            reason = Reason.COMPLETED;
        } else if (!started) {
            reason = Reason.START_NOT_CONFIRMED;
        } else if (points.stream().noneMatch(p -> p.s() != null && p.s() >= finishFrom)) {
            reason = Reason.FINISH_NOT_REACHED;
        } else {
            reason = Reason.DISTANCE_SHORT;
        }

        long startMs = inputs.stream().filter(i -> i.kind() == Kind.START)
                .mapToLong(Input::elapsedMs).findFirst().orElse(0);
        long endMs = completion != null ? completion.point().elapsedMs() : segmentEndMs(inputs);
        long elapsedMs = Math.max(0, endMs - startMs);
        long movingMs = Math.max(0, elapsedMs - pausedMs(inputs, endMs));

        double meters = recognized.meters();
        Judgement judgement = new Judgement(
                recognized.ranges(),
                meters,
                length,
                Math.min(100, meters / length * 100),
                completion != null,
                reason,
                completion != null ? completion.point().measuredAt() : null,
                toSeconds(elapsedMs),
                toSeconds(movingMs),
                meters + EPSILON_M >= Math.max(REVIEW_MIN_M, length * REVIEW_RATIO));
        var bySeq = inputs.stream().collect(java.util.stream.Collectors.toMap(Input::seq, i -> i, (a, b) -> b));
        List<CourseSample> samples = points.stream().map(p -> {
            Input input = bySeq.get(p.seq());
            boolean ambiguous = p.s() == null && com.wadadak.run.internal.GpsQuality.good(input)
                    && route.candidates(route.toLocal(input.location()), config.routeToleranceM()).size() > 1;
            return new CourseSample(p.seq(), p.elapsedMs(), p.s(), p.connected(), ambiguous);
        }).toList();
        return new Analysis(judgement, samples, elapsedMs);
    }

    /** 출발 확인: 처음으로 코스상 위치를 정한 표본이 출발점 반경 안(s ≤ 시작 반경). C-04처럼 중간에서 시작하면 실패 */
    private boolean startConfirmed(List<Point> points) {
        return points.stream().map(Point::s).filter(Objects::nonNull).findFirst()
                .map(s -> s <= config.startRadiusM() + EPSILON_M)
                .orElse(false);
    }

    /**
     * 끝 도달과 거리 조건을 처음 함께 충족한 표본. 끝 도달은 코스상 위치로 보므로 순환 코스 출발점을 끝으로 보지 않는다.
     * 처음 충족 시점에 고정해 두 바퀴째(S-06)나 앱의 늦은 구간 종료(B-04)가 완주 시각을 바꾸지 않는다.
     * ponytail: 끝 구간(전체 − 끝 도달 오차)에 처음 들어선 표본을 완주로 보므로 실제 도착보다 최대 끝 도달 오차만큼
     * (30m ≈ 10초) 이르다. 2026-10-16 오차를 그대로 두기로 함. 정확한 시각이 필요하면 끝 지점 통과 시각을 보간한다
     */
    private static Progress firstCompletion(RecognizedDistance recognized, double finishFrom, double required) {
        boolean finishReached = false;
        for (Progress progress : recognized.timeline()) {
            Double s = progress.point().s();
            if (s != null && s >= finishFrom) {
                finishReached = true;
            }
            if (finishReached && progress.recognizedM() + EPSILON_M >= required) {
                return progress;
            }
        }
        return null;
    }

    /** 코스 구간이 끝난 시점: 처음 SEGMENT_END, 없으면 END, 둘 다 없으면 마지막 입력 */
    private static long segmentEndMs(List<Input> inputs) {
        return inputs.stream()
                .filter(i -> i.kind() == Kind.SEGMENT_END || i.kind() == Kind.END)
                .mapToLong(Input::elapsedMs).findFirst()
                .orElse(inputs.isEmpty() ? 0 : inputs.getLast().elapsedMs());
    }

    /** endMs까지의 일시정지 시간 합. 재개 없이 끝나면 endMs까지 정지로 본다 */
    private static long pausedMs(List<Input> inputs, long endMs) {
        long paused = 0;
        Long pausedAt = null;
        for (Input input : inputs) {
            if (input.elapsedMs() > endMs) {
                break;
            }
            if (input.kind() == Kind.PAUSE && pausedAt == null) {
                pausedAt = input.elapsedMs();
            } else if (input.kind() == Kind.RESUME && pausedAt != null) {
                paused += input.elapsedMs() - pausedAt;
                pausedAt = null;
            }
        }
        if (pausedAt != null) {
            paused += endMs - pausedAt;
        }
        return paused;
    }

    /** ponytail: floor(ms / 1000) 잠정(판정 기대값 B-05). ranking과 계약 PR에서 확정되면 맞춘다 */
    private static long toSeconds(long ms) {
        return Math.floorDiv(ms, 1000);
    }
}
