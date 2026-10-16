package com.wadadak.run.internal.judging;

import com.wadadak.run.internal.judging.CourseTracker.Point;
import com.wadadak.run.internal.judging.CourseTrackerTest.Run;
import com.wadadak.run.internal.judging.RecognizedDistance.Progress;
import com.wadadak.run.internal.judging.RecognizedDistance.Range;
import com.wadadak.run.internal.judging.RunInput.Kind;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import static com.wadadak.run.internal.judging.RouteGeometryTest.K3;
import static com.wadadak.run.internal.judging.RouteGeometryTest.K4;
import static com.wadadak.run.internal.judging.RouteGeometryTest.K5;
import static com.wadadak.run.internal.judging.RouteGeometryTest.course;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

class RecognizedDistanceTest {

    /** 판정 기대값 K2: (0,0) → (0,5000) 직선 5,000m */
    static final RouteGeometry K2 = course(0, 0, 0, 5000);

    // ---- 4단계만: 손으로 만든 추적 결과 ----

    /** (s, 직전과 연결) 쌍을 순서대로 받아 추적 결과를 만든다. s가 NaN이면 코스 밖 */
    static List<Point> points(Object... sAndConnected) {
        List<Point> points = new ArrayList<>();
        for (int i = 0; i < sAndConnected.length; i += 2) {
            double s = ((Number) sAndConnected[i]).doubleValue();
            points.add(new Point(i / 2, i * 1000L, Instant.EPOCH.plusSeconds(i), Double.isNaN(s) ? null : s,
                    (Boolean) sAndConnected[i + 1]));
        }
        return points;
    }

    @Test
    void connectedForwardPairsAreRecognized() {
        RecognizedDistance r = RecognizedDistance.of(points(0, false, 5, true, 10, true));

        assertThat(r.ranges()).containsExactly(new Range(0, 10));
        assertThat(r.meters()).isEqualTo(10);
    }

    @Test
    void disconnectedStepIsNotRecognized() {
        RecognizedDistance r = RecognizedDistance.of(points(0, false, 100, true, 300, false, 400, true));

        assertThat(r.ranges()).containsExactly(new Range(0, 100), new Range(300, 400));
        assertThat(r.meters()).isEqualTo(200);
    }

    @Test
    void backwardStepIsNotRecognizedAndRepeatCountsOnce() {
        RecognizedDistance r = RecognizedDistance.of(points(0, false, 1000, true, 500, true, 1000, true));

        assertThat(r.ranges()).containsExactly(new Range(0, 1000));
        assertThat(r.meters()).isEqualTo(1000);
    }

    @Test
    void offRoutePointBreaksNothingByItself() {
        RecognizedDistance r = RecognizedDistance.of(points(0, false, 50, true, Double.NaN, false, 60, false, 80, true));

        assertThat(r.ranges()).containsExactly(new Range(0, 50), new Range(60, 80));
    }

    @Test
    void touchingRangesMerge() {
        RecognizedDistance r = RecognizedDistance.of(points(0, false, 100, true, 100, false, 200, true));

        assertThat(r.ranges()).containsExactly(new Range(0, 200));
    }

    @Test
    void timelineHoldsRecognizedDistanceSoFar() {
        RecognizedDistance r = RecognizedDistance.of(points(0, false, 100, true, 50, true, 300, false, 400, true));

        assertThat(r.timeline()).extracting(Progress::recognizedM).containsExactly(0.0, 100.0, 100.0, 100.0, 200.0);
    }

    // ---- 3·4단계 함께: 판정 기대값(run/판정 기대값 - 2026-10-12)의 인정 거리 ----

    static double recognized(RouteGeometry route, Run run) {
        return RecognizedDistance.of(new CourseTracker(route, JudgingConfig.DEFAULTS).track(run.inputs)).meters();
    }

    @Test
    void c01FullCourse() {
        assertThat(recognized(K2, new Run().at(0, 0).walk(0, 5000))).isCloseTo(5000, within(1e-6));
    }

    @Test
    void c02DetourSkips250() {
        Run run = new Run().at(0, 0).walk(0, 2000).walk(300, 2000).walk(300, 2250).walk(0, 2250).walk(0, 5000);
        assertThat(recognized(K2, run)).isCloseTo(4750, within(1e-6));
    }

    @Test
    void c03DetourSkips251() {
        Run run = new Run().at(0, 0).walk(0, 2000).walk(300, 2000).walk(300, 2251).walk(0, 2251).walk(0, 5000);
        assertThat(recognized(K2, run)).isCloseTo(4749, within(1e-6));
    }

    @Test
    void r01ShortcutCountsOnlyRunParts() {
        Run run = new Run().at(0, 0).walk(0, 1000).walk(300, 1000).walk(300, 4000).walk(0, 4000).walk(0, 5000);
        assertThat(recognized(K2, run)).isCloseTo(2000, within(1e-6));
    }

    @Test
    void r02ReverseAndRepeatCountOnce() {
        Run run = new Run().at(0, 0).walk(0, 1000).walk(0, 0).walk(0, 1000);
        assertThat(recognized(K2, run)).isCloseTo(1000, within(1e-6));
    }

    @Test
    void r03MovementWhilePausedExcluded() {
        // 재개 뒤 첫 표본(s = 1,500)이 새 기준점
        Run run = new Run().at(0, 0).walk(0, 1000)
                .event(Kind.PAUSE).walk(0, 1500).event(Kind.RESUME).at(0, 1500).walk(0, 5000);
        assertThat(recognized(K2, run)).isCloseTo(4500, within(1e-6));
    }

    @Test
    void r04GapNotBridged() {
        Run run = new Run().at(0, 0).walk(0, 2000).event(Kind.GAP).at(0, 2300).walk(0, 5000);
        assertThat(recognized(K2, run)).isCloseTo(4700, within(1e-6));
    }

    @Test
    void r05SingleCrossingIsZero() {
        Run run = new Run().at(-200, 2500).walk(200, 2500, 50, 10_000);
        assertThat(recognized(K2, run)).isZero();
    }

    @Test
    void s01OutAndBackBothLegs() {
        assertThat(recognized(K3, new Run().at(0, 0).walk(0, 1000).walk(0, 0))).isCloseTo(2000, within(1e-6));
    }

    @Test
    void s02OutOnly() {
        assertThat(recognized(K3, new Run().at(0, 0).walk(0, 1000).event(Kind.END))).isCloseTo(1000, within(1e-6));
    }

    @Test
    void s03S04StandingAtStartIsZero() {
        assertThat(recognized(K3, new Run().at(0, 0).stay(60).event(Kind.END))).isZero();
        assertThat(recognized(K4, new Run().at(0, 0).stay(60).event(Kind.END))).isZero();
    }

    @Test
    void s06SecondLapNotAdded() {
        Run run = new Run().at(0, 0).walk(500, 0).walk(500, 500).walk(0, 500).walk(0, 0).walk(500, 0);
        assertThat(recognized(K4, run)).isCloseTo(2000, within(1e-6));
    }

    @Test
    void s07FigureEightWhole() {
        Run run = new Run().at(0, 0).walk(300, 300).walk(300, 0).walk(0, 300);
        assertThat(recognized(K5, run)).isCloseTo(K5.length(), within(1e-6));
    }

    @Test
    void b01LongDetourBackToSamePoint() {
        Run run = new Run().at(0, 0).walk(0, 3000).walk(300, 3000).stay(600).walk(0, 3000).walk(0, 5000);
        assertThat(recognized(K2, run)).isCloseTo(5000, within(1e-6));
    }

    @Test
    void b01bLongDetourBackFurther() {
        Run run = new Run().at(0, 0).walk(0, 3000).walk(300, 3000).stay(600).walk(300, 3300).walk(0, 3300).walk(0, 5000);
        assertThat(recognized(K2, run)).isCloseTo(4700, within(1e-6));
    }

    @Test
    void b02RunAfterSegmentEndNotCounted() {
        Run run = new Run().at(0, 0).walk(0, 4800)
                .event(Kind.PAUSE).event(Kind.SEGMENT_END).event(Kind.RESUME).walk(0, 5000).event(Kind.END);
        assertThat(recognized(K2, run)).isCloseTo(4800, within(1e-6));
    }
}
