package com.wadadak.run.internal.judging;

import com.wadadak.run.internal.judging.CourseTracker.Point;
import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.RunContracts.Kind;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

import static com.wadadak.run.internal.judging.RouteGeometryTest.K1;
import static com.wadadak.run.internal.judging.RouteGeometryTest.K3;
import static com.wadadak.run.internal.judging.RouteGeometryTest.K4;
import static com.wadadak.run.internal.judging.RouteGeometryTest.K5;
import static com.wadadak.run.internal.judging.RouteGeometryTest.geo;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/**
 * 코스 K1·K3·K4·K5와 사례 번호는 판정 기대값(run/판정 기대값 - 2026-10-12).
 */
class CourseTrackerTest {

    /** 로컬 평면(m) 위를 움직이며 세션 입력을 만든다. 기본 2초에 5m(2.5m/s), 정확도 5m */
    static final class Run {
        static final Instant T0 = Instant.parse("2026-10-15T00:00:00Z");

        final List<Input> inputs = new ArrayList<>();
        long ms;
        double x;
        double y;

        Run() {
            add(Kind.START, null);
        }

        /** 현재 위치에서 (toX, toY)까지 step(m)마다 표본, 표본 사이 stepMs */
        Run walk(double toX, double toY, double step, long stepMs) {
            double length = Math.hypot(toX - x, toY - y);
            int n = (int) Math.ceil(length / step);
            double fromX = x;
            double fromY = y;
            for (int i = 1; i <= n; i++) {
                x = fromX + (toX - fromX) * i / n;
                y = fromY + (toY - fromY) * i / n;
                ms += stepMs;
                gps(5.0);
            }
            return this;
        }

        Run walk(double toX, double toY) {
            return walk(toX, toY, 5, 2000);
        }

        /** 그 자리로 옮겨 표본 하나(첫 표본·공백 뒤 첫 표본용) */
        Run at(double atX, double atY) {
            x = atX;
            y = atY;
            ms += 2000;
            return gps(5.0);
        }

        Run stay(int seconds) {
            for (int i = 0; i < seconds / 2; i++) {
                ms += 2000;
                gps(5.0);
            }
            return this;
        }

        Run gps(double accuracyM) {
            inputs.add(new Input(inputs.size(), Kind.GPS, ms, T0.plusMillis(ms), geo(x, y), accuracyM, null));
            return this;
        }

        Run event(Kind kind) {
            return add(kind, null);
        }

        private Run add(Kind kind, Double accuracyM) {
            inputs.add(new Input(inputs.size(), kind, ms, T0.plusMillis(ms), null, accuracyM, null));
            return this;
        }
    }

    static List<Point> track(RouteGeometry route, Run run) {
        return new CourseTracker(route, JudgingConfig.DEFAULTS).track(run.inputs);
    }

    static List<Double> placed(List<Point> points) {
        return points.stream().map(Point::s).filter(Objects::nonNull).toList();
    }

    static Point at(List<Point> points, double s) {
        return points.stream().filter(p -> p.s() != null && Math.abs(p.s() - s) < 0.5).findFirst().orElseThrow();
    }

    @Test
    void straightRouteIsTrackedAndConnected() {
        List<Point> points = track(K1, new Run().at(0, 0).walk(0, 1000));

        assertThat(points).allSatisfy(p -> assertThat(p.s()).isNotNull());
        assertThat(points.getFirst().connected()).isFalse();
        assertThat(points.subList(1, points.size())).allSatisfy(p -> assertThat(p.connected()).isTrue());
        assertThat(points.getLast().s()).isCloseTo(1000, within(1e-6));
    }

    @Test
    void loopStartIsHeldThenResolvedToZero() {
        // K4 출발점은 s = 0과 2,000 두 후보. 동쪽으로 가면 0으로 정해지고 보류했던 첫 표본도 0이 된다
        List<Point> points = track(K4, new Run().at(0, 0).walk(500, 0));

        assertThat(points.getFirst().s()).isCloseTo(0, within(1e-6));
        assertThat(placed(points)).isSorted().hasSize(points.size());
        assertThat(points.getLast().s()).isCloseTo(500, within(1e-6));
    }

    @Test
    void standingAtLoopStartStaysHeld() {
        // S-04: 순환 코스 출발점에 60초 머문 뒤 END → 끝까지 정하지 못함
        List<Point> points = track(K4, new Run().at(0, 0).stay(60).event(Kind.END));

        assertThat(placed(points)).isEmpty();
    }

    @Test
    void fullLoopEndsAtFinishNotStart() {
        // S-05: 한 바퀴 끝(0,0)은 s = 2,000
        List<Point> points = track(K4, new Run().at(0, 0).walk(500, 0).walk(500, 500).walk(0, 500).walk(0, 0));

        assertThat(placed(points)).isSorted();
        assertThat(points.getLast().s()).isCloseTo(2000, within(1e-6));
    }

    @Test
    void outAndBackTakesReturnLegAfterTurnaround() {
        // S-01: K3 갔다가 돌아옴. 출발점 보류는 정방향(0)으로, 반환점 뒤는 돌아오는 길(1,000~2,000)로
        List<Point> points = track(K3, new Run().at(0, 0).walk(0, 1000).walk(0, 0));

        assertThat(points.getFirst().s()).isCloseTo(0, within(1e-6));
        assertThat(placed(points)).isSorted().hasSize(points.size());
        assertThat(points.getLast().s()).isCloseTo(2000, within(1e-6));
    }

    @Test
    void figureEightCrossingDoesNotConfuseLegs() {
        // S-07: 교차점 (150,150)을 두 번 지나도 s는 계속 늘어난다
        List<Point> points = track(K5, new Run().at(0, 0).walk(300, 300).walk(300, 0).walk(0, 300));

        assertThat(placed(points)).isSorted().hasSize(points.size());
        assertThat(points.getLast().s()).isCloseTo(K5.length(), within(1e-6));
    }

    @Test
    void crossingAfterGapIsHeldUntilDirectionIsKnown() {
        // S-08: GAP 뒤 첫 표본이 교차점이면 s≈212.1·936.4 중 특정 불가로 보류. 첫 갈래 방향으로 가면 212.1로 정해진다
        List<Point> points = track(K5, new Run().at(0, 0).walk(100, 100).event(Kind.GAP).at(150, 150).walk(250, 250));

        Point crossing = at(points, 212.13);
        assertThat(crossing.connected()).isFalse();
        assertThat(placed(points)).isSorted().hasSize(points.size());
    }

    @Test
    void reverseRunIsTrackedBackward() {
        // R-02: 역방향도 위치는 따라간다. 인정하지 않는 것은 4단계 몫
        List<Point> points = track(K1, new Run().at(0, 0).walk(0, 500).walk(0, 0));

        assertThat(points.getLast().s()).isCloseTo(0, within(1e-6));
        assertThat(points.getLast().connected()).isTrue();
    }

    @Test
    void singleCrossingSampleIsNotConnected() {
        // R-05: 코스 밖에서 동서로 달리다 한 번 가로지름. 경로 위 표본은 1개, 앞뒤와 연결되지 않는다
        List<Point> points = track(K1, new Run().at(-200, 500).walk(200, 500, 50, 10_000));

        assertThat(placed(points)).hasSize(1);
        assertThat(points).allSatisfy(p -> assertThat(p.connected()).isFalse());
    }

    @Test
    void movementWhilePausedIsIgnored() {
        // R-03: 정지 중 경로 위 이동은 버리고, 재개 뒤 첫 표본은 앞과 잇지 않는다
        List<Point> points = track(K1, new Run().at(0, 0).walk(0, 300)
                .event(Kind.PAUSE).walk(0, 500).event(Kind.RESUME).walk(0, 600));

        assertThat(placed(points)).noneMatch(s -> s > 300 && s < 500);
        assertThat(at(points, 505).connected()).isFalse();
        assertThat(at(points, 510).connected()).isTrue();
    }

    @Test
    void gapIsNotBridged() {
        // R-04: 공백 뒤 첫 표본(s = 300)은 앞(s = 200)과 잇지 않는다
        List<Point> points = track(K1, new Run().at(0, 0).walk(0, 200).event(Kind.GAP).at(0, 300).walk(0, 400));

        assertThat(at(points, 300).connected()).isFalse();
        assertThat(at(points, 305).connected()).isTrue();
    }

    @Test
    void inputsAfterSegmentEndAreDropped() {
        List<Point> points = track(K1, new Run().at(0, 0).walk(0, 500).event(Kind.SEGMENT_END).walk(0, 1000));

        assertThat(points.getLast().s()).isCloseTo(500, within(1e-6));
    }

    @Test
    void poorAccuracySampleBreaksConnection() {
        Run run = new Run().at(0, 0).walk(0, 100);
        run.ms += 2000;
        run.y = 105;
        run.gps(50); // 정확도 30m 초과
        List<Point> points = track(K1, run.walk(0, 200));

        Point poor = points.get(points.size() - 20);
        assertThat(poor.s()).isNull();
        assertThat(at(points, 110).connected()).isFalse();
        assertThat(at(points, 115).connected()).isTrue();
    }

    @Test
    void gpsErrorOnShortIntervalStaysConnected() {
        // 1초 간격 6m/s 주행인데 오차로 앞 표본은 5m 뒤, 뒤 표본은 5m 앞에 찍힘: 좌표상 16m > 12m지만 정확도 5m + 5m 여유로 연결
        List<Point> points = track(K1, new Run().at(0, 0).walk(0, 100).walk(0, 95, 5, 1000).walk(0, 111, 16, 1000));

        assertThat(points.getLast().s()).isCloseTo(111, within(1e-6));
        assertThat(points.getLast().connected()).isTrue();
    }

    @Test
    void jumpAlongRouteIsNotConnected() {
        // 2초 만에 경로를 따라 300m: 창(12m/s × 2초 + 20m) 밖이라 점프, 건너뛴 구간을 잇지 않는다
        List<Point> points = track(K1, new Run().at(0, 0).walk(0, 100).at(0, 400).walk(0, 450));

        assertThat(at(points, 400).connected()).isFalse();
        assertThat(at(points, 405).connected()).isTrue();
    }
}
