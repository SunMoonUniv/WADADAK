package com.wadadak.run.internal.judging;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.run.internal.judging.CourseJudge.Judgement;
import com.wadadak.run.internal.judging.CourseJudge.Reason;
import com.wadadak.run.internal.judging.CourseTrackerTest.Run;
import com.wadadak.run.internal.RunContracts.Kind;
import com.wadadak.run.internal.RunContracts.Input;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static com.wadadak.run.internal.judging.RouteGeometryTest.geo;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * 판정 기대값(run/판정 기대값 - 2026-10-12)의 최종 결과. 기대값은 문서 값을 그대로 쓴다.
 */
class CourseJudgeTest {

    static CourseRouteSnapshot course(int totalDistanceMeters, double... xy) {
        List<GeoPoint> route = new ArrayList<>();
        for (int i = 0; i < xy.length; i += 2) {
            route.add(geo(xy[i], xy[i + 1]));
        }
        return new CourseRouteSnapshot(UUID.randomUUID(), "테스트 코스", route, totalDistanceMeters, 0);
    }

    static final CourseRouteSnapshot K1 = course(1000, 0, 0, 0, 1000);
    static final CourseRouteSnapshot K2 = course(5000, 0, 0, 0, 5000);
    static final CourseRouteSnapshot K6 = course(10000, 0, 0, 0, 10000);
    static final CourseRouteSnapshot K3 = course(2000, 0, 0, 0, 1000, 0, 0);
    static final CourseRouteSnapshot K4 = course(2000, 0, 0, 500, 0, 500, 500, 0, 500, 0, 0);
    static final CourseRouteSnapshot K5 = course(1149, 0, 0, 300, 300, 300, 0, 0, 300);

    static Judgement judge(CourseRouteSnapshot course, Run run) {
        return new CourseJudge(JudgingConfig.DEFAULTS).judge(course, run.inputs);
    }

    static void assertResult(Judgement j, double recognizedM, double progress, boolean completed, boolean review) {
        assertThat(j.recognizedM()).isCloseTo(recognizedM, within(1e-6));
        assertThat(j.progressPercent()).isCloseTo(progress, within(0.005));
        assertThat(j.completed()).isEqualTo(completed);
        assertThat(j.reviewEligible()).isEqualTo(review);
    }

    @Test
    void barometerSamplesDoNotChangeCourseJudgement() {
        var original = new Run().at(0,0).walk(0,5000).event(Kind.END).inputs;
        var withPressure = new ArrayList<Input>();
        for (Input p : original) {
            withPressure.add(new Input(withPressure.size(),p.kind(),p.elapsedMs(),p.measuredAt(),p.location(),p.accuracyM(),
                p.reason(),p.speedMps(),p.speedAccuracyMps(),p.steps(),p.durationMs(),p.sampleEndMs(),p.altitudeM(),p.altitudeAccuracyM()));
            if (p.kind() == Kind.GPS) withPressure.add(new Input(withPressure.size(),Kind.BAROMETER,p.elapsedMs(),p.measuredAt(),
                null,null,null,null,null,null,null,p.elapsedMs(),null,null,1000.0,3));
        }
        var judge = new CourseJudge(JudgingConfig.DEFAULTS);
        assertThat(judge.judge(K2,withPressure)).isEqualTo(judge.judge(K2,original));
    }

    // ---- 4장 완주 경계 ----

    @Test
    void c01Normal() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 5000));
        assertResult(j, 5000, 100, true, true);
        assertThat(j.reason()).isEqualTo(Reason.COMPLETED);
        assertThat(j.completedAt()).isNotNull();
    }

    @Test
    void c02NinetyFivePercentBoundaryCompletes() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 2000).walk(300, 2000).walk(300, 2250).walk(0, 2250).walk(0, 5000));
        assertResult(j, 4750, 95.0, true, true);
    }

    @Test
    void c03JustBelowNinetyFivePercent() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 2000).walk(300, 2000).walk(300, 2251).walk(0, 2251).walk(0, 5000));
        assertResult(j, 4749, 94.98, false, true);
        assertThat(j.reason()).isEqualTo(Reason.DISTANCE_SHORT);
    }

    @Test
    void c04StartNotConfirmed() {
        Judgement j = judge(K2, new Run().at(0, 200).walk(0, 5000));
        assertResult(j, 4800, 96, false, true);
        assertThat(j.reason()).isEqualTo(Reason.START_NOT_CONFIRMED);
    }

    @Test
    void c05FinishNotReached() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 4800).event(Kind.END));
        assertResult(j, 4800, 96, false, true);
        assertThat(j.reason()).isEqualTo(Reason.FINISH_NOT_REACHED);
    }

    @Test
    void c06CompletedButTooShortForReview() {
        Judgement j = judge(K1, new Run().at(0, 0).walk(0, 400).walk(300, 400).walk(300, 450).walk(0, 450).walk(0, 1000));
        assertResult(j, 950, 95, true, false);
    }

    // ---- 5장 리뷰 경계 (모두 미완주) ----

    @Test
    void v01ReviewAtOneKilometer() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 1000).walk(300, 1000).walk(300, 2700));
        assertResult(j, 1000, 20, false, true);
    }

    @Test
    void v02OffRouteDistanceDoesNotCount() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 800).walk(300, 800).walk(300, 2500));
        assertResult(j, 800, 16, false, false);
    }

    @Test
    void v03TenKilometerCourseNeedsTwoKilometers() {
        Judgement j = judge(K6, new Run().at(0, 0).walk(0, 1999).event(Kind.END));
        assertResult(j, 1999, 19.99, false, false);
    }

    @Test
    void v04TenKilometerCourseAtTwoKilometers() {
        Judgement j = judge(K6, new Run().at(0, 0).walk(0, 2000).event(Kind.END));
        assertResult(j, 2000, 20, false, true);
    }

    // ---- 6·7장 구간·경로 모양의 완주 여부 ----

    @Test
    void r01ShortcutReachesFinishButIsShort() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 1000).walk(300, 1000).walk(300, 4000).walk(0, 4000).walk(0, 5000));
        assertResult(j, 2000, 40, false, true);
        assertThat(j.reason()).isEqualTo(Reason.DISTANCE_SHORT);
    }

    @Test
    void s02OutAndBackStoppedAtTurnaround() {
        Judgement j = judge(K3, new Run().at(0, 0).walk(0, 1000).event(Kind.END));
        assertResult(j, 1000, 50, false, true);
    }

    @Test
    void s03S04StandingAtStartNeverCompletes() {
        assertResult(judge(K3, new Run().at(0, 0).stay(60).event(Kind.END)), 0, 0, false, false);
        assertResult(judge(K4, new Run().at(0, 0).stay(60).event(Kind.END)), 0, 0, false, false);
    }

    @Test
    void s05AndS06CompletionFixedAtFirstLap() {
        Judgement oneLap = judge(K4, new Run().at(0, 0).walk(500, 0).walk(500, 500).walk(0, 500).walk(0, 0));
        Judgement twoLaps = judge(K4, new Run().at(0, 0).walk(500, 0).walk(500, 500).walk(0, 500).walk(0, 0).walk(500, 0));

        assertResult(oneLap, 2000, 100, true, true);
        assertResult(twoLaps, 2000, 100, true, true);
        assertThat(twoLaps.completedAt()).isEqualTo(oneLap.completedAt());
    }

    @Test
    void s07FigureEightCompletes() {
        Judgement j = judge(K5, new Run().at(0, 0).walk(300, 300).walk(300, 0).walk(0, 300));
        assertResult(j, j.courseLengthM(), 100, true, true);
    }

    // ---- 8장 구간 경계와 시간 ----

    @Test
    void b01LongDetourStillCompletes() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 3000).walk(300, 3000).stay(600).walk(0, 3000).walk(0, 5000).event(Kind.END));
        assertResult(j, 5000, 100, true, true);
    }

    @Test
    void b01bLongDetourSkipsTooMuch() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 3000).walk(300, 3000).stay(600)
                .walk(300, 3300).walk(0, 3300).walk(0, 5000).event(Kind.END));
        assertResult(j, 4700, 94, false, true);
    }

    @Test
    void b02FinishAfterSegmentEndDoesNotCount() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 4800)
                .event(Kind.PAUSE).event(Kind.SEGMENT_END).event(Kind.RESUME).walk(0, 5000).event(Kind.END));
        assertResult(j, 4800, 96, false, true);
        assertThat(j.reason()).isEqualTo(Reason.FINISH_NOT_REACHED);
    }

    @Test
    void b02bNoSegmentEndUsesSessionEnd() {
        Judgement j = judge(K2, new Run().at(0, 0).walk(0, 4800).event(Kind.END));
        assertResult(j, 4800, 96, false, true);
    }

    /**
     * B-03: 0→5,000(정지 180초 포함 총 1,800초), 끝에서 SEGMENT_END, 자유 러닝 600초 뒤 END.
     * 5m를 1.62초에 달려 달린 시간 1,620초.
     */
    static Run b03(long segmentEndDelayMs) {
        Run run = new Run();
        run.gps(5.0);                                  // 0ms, 출발점
        run.walk(0, 2500, 5, 1620);                    // 810,000ms
        run.event(Kind.PAUSE);
        run.ms += 180_000;                             // 990,000ms
        run.event(Kind.RESUME);
        run.gps(5.0);                                  // 재개 위치 s = 2,500
        run.walk(0, 5000, 5, 1620);                    // 1,800,000ms 도착
        if (segmentEndDelayMs > 0) {                   // B-04: 앱의 도착 감지가 늦어 계속 달림
            run.walk(0, 5000 + segmentEndDelayMs / 1620 * 5, 5, 1620);
        }
        run.event(Kind.SEGMENT_END);
        run.walk(300, 5000 + 1000);                    // 자유 러닝
        run.event(Kind.END);
        return run;
    }

    /**
     * 실제 도착은 1,800,000ms지만 완주 시각은 끝 구간(끝 도달 오차 30m)에 처음 들어선 s = 4,970 표본이다.
     * 2,500 → 4,970이 494걸음 × 1,620ms라 990,000 + 800,280 = 1,790,280ms.
     * 판정 기대값의 1,800초는 끝 지점 도착 기준이고, 끝 도달 오차만큼 이른 이 차이는 그대로 두기로 했다(2026-10-16)
     */
    static final long B03_COMPLETION_MS = 1_790_280;

    @Test
    void b03CourseTimeStopsAtFinishZone() {
        Judgement j = judge(K2, b03(0));
        assertResult(j, 5000, 100, true, true);
        assertThat(j.courseElapsedSeconds()).isEqualTo(1790);
        assertThat(j.courseMovingSeconds()).isEqualTo(1610);
    }

    @Test
    void b04LateSegmentEndKeepsServerFinishTime() {
        Judgement j = judge(K2, b03(30_000));
        assertThat(j.completed()).isTrue();
        assertThat(j.courseElapsedSeconds()).isEqualTo(1790);
        assertThat(j.completedAt()).isEqualTo(Run.T0.plusMillis(B03_COMPLETION_MS));
    }

    @Test
    void b05SecondsAreFloored() {
        Run run = new Run().at(0, 0).walk(0, 500);
        run.ms = 1_800_999;
        Judgement j = judge(K1, run.event(Kind.END));
        assertThat(j.courseElapsedSeconds()).isEqualTo(1800);
    }
}
