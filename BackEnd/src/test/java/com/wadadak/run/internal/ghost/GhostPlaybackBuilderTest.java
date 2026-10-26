package com.wadadak.run.internal.ghost;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.judging.CourseJudge;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class GhostPlaybackBuilderTest {
    final JsonMapper json = JsonMapper.builder().findAndAddModules().build();
    final GhostPlaybackBuilder builder = new GhostPlaybackBuilder();
    final Instant start = Instant.parse("2026-10-26T00:00:00Z");
    final UUID recordId = UUID.randomUUID(), courseId = UUID.randomUUID();
    static final double LAT = 36.799, LNG = 127.075;
    static final double LAT_PER_M = 1 / (GeoPoint.EARTH_RADIUS_M * Math.PI / 180);
    final List<GeoPoint> route = List.of(point(0), point(1000));
    GeoPoint point(double m) { return new GeoPoint(LAT + m * LAT_PER_M, LNG); }
    CourseSnapshot snapshot() { return new CourseSnapshot(recordId, courseId, "합성 코스", route, 1000, 3); }

    Result source(List<Input> raw) {
        var j = new CourseJudge().judge(new CourseRouteSnapshot(courseId, "합성 코스", route, 1000, 3), raw);
        var course = new CourseOutcome(courseId, "합성 코스", 3, 1000, j.completed(), j.reason().name(),
                j.recognizedM(), j.progressPercent(), j.completedAt(), j.courseElapsedSeconds(),
                j.courseMovingSeconds(), j.reviewEligible());
        return new Result(recordId, start, raw.getLast().measuredAt(), start.plusSeconds(9000), "USER",
                new Metrics(1000, raw.getLast().elapsedMs(), raw.getLast().elapsedMs(), 0, null),
                List.of(), List.of(), "2026-10-14", "PACE_V3", null, course);
    }

    @Test void sharedFixturesPreservePauseGapsAndCourseBoundaryWithoutChangingSource() throws Exception {
        var fixture = json.readTree(Files.readString(Path.of("../run/fixtures/ghost_playback_v1.json")));
        for (var c : fixture.get("cases")) {
            List<Input> raw = new ArrayList<>();
            for (var input : c.get("inputs")) raw.add(json.treeToValue(input, Input.class));
            Result source = source(raw);
            assertThat(source.course().completed()).as(c.get("name").asText()).isTrue();
            String before = json.writeValueAsString(source), rawBefore = json.writeValueAsString(raw);
            GhostPlayback result = builder.build(source, snapshot(), raw);
            JsonNode expected = c.get("expected");
            assertThat(result.eligible()).as(c.get("name").asText()).isTrue();
            assertThat(result.durationMs()).isEqualTo(expected.get("durationMs").asLong());
            assertThat(result.quality()).isEqualTo(json.treeToValue(expected.get("quality"), GhostQuality.class));
            assertThat(result.spans()).hasSize(expected.get("spans").size());
            for (int i = 0; i < result.spans().size(); i++) {
                GhostSpan actual = result.spans().get(i), wanted = json.treeToValue(expected.get("spans").get(i), GhostSpan.class);
                assertThat(actual.fromMs()).isEqualTo(wanted.fromMs());
                assertThat(actual.toMs()).isEqualTo(wanted.toMs());
                assertThat(actual.state()).isEqualTo(wanted.state());
                if (wanted.fromPositionM() == null) {
                    assertThat(actual.fromPositionM()).isNull();
                    assertThat(actual.toPositionM()).isNull();
                } else {
                    assertThat(actual.fromPositionM()).isCloseTo(wanted.fromPositionM(), within(1e-6));
                    assertThat(actual.toPositionM()).isCloseTo(wanted.toPositionM(), within(1e-6));
                }
            }
            assertThat(json.writeValueAsString(source)).isEqualTo(before);
            assertThat(json.writeValueAsString(raw)).isEqualTo(rawBefore);
            assertThat(json.readValue(json.writeValueAsString(result), GhostPlayback.class)).isEqualTo(result);
        }
    }

    /** Dense 0.485m/s source: finish tolerance first qualifies at 2,000,000ms / 970m.
     * Gaps retain the same coordinate at both ends so quality tests do not lose recognized distance. */
    List<Input> qualityRun(List<long[]> gaps) {
        TreeSet<Long> times = new TreeSet<>();
        for (long ms = 0; ms <= 2_000_000; ms += 2000) times.add(ms);
        for (long[] gap : gaps) {
            times.removeIf(ms -> ms > gap[0] && ms < gap[1]);
            times.add(gap[0]); times.add(gap[1]);
        }
        List<Input> raw = new ArrayList<>();
        raw.add(input(0, Kind.START, 0, null, "PACE_V3"));
        double activeMs = 2_000_000 - gaps.stream().mapToLong(g -> g[1] - g[0]).sum();
        for (long ms : times) {
            double removed = 0;
            for (long[] gap : gaps) removed += Math.max(0, Math.min(ms, gap[1]) - gap[0]);
            double position = 970 * (ms - removed) / activeMs;
            // Stop just below the finish threshold until the final exact point.
            raw.add(input(raw.size(), Kind.GPS, ms, point(position), null));
            for (long[] gap : gaps) {
                if (ms == gap[0] && gap[1] - gap[0] <= 10_000)
                    raw.add(input(raw.size(), Kind.GAP, ms + 1, null, "NO_FIX"));
            }
        }
        raw.add(input(raw.size(), Kind.END, 2_001_000, null, "INTERRUPTED"));
        return raw;
    }
    Input input(long seq, Kind kind, long ms, GeoPoint location, String reason) {
        return new Input(seq, kind, ms, start.plusMillis(ms), location, kind == Kind.GPS ? 5.0 : null, reason);
    }

    @Test void continuousGapIncludesThirtySecondsAndRejectsOneMillisecondMore() {
        for (long length : List.of(30_000L, 30_001L)) {
            var raw = qualityRun(List.of(new long[]{100_000, 100_000 + length}));
            var result = builder.build(source(raw), snapshot(), raw);
            assertThat(result.durationMs()).isEqualTo(2_000_000L);
            assertThat(result.quality().maxGapMs()).isEqualTo(length);
            assertThat(result.eligible()).isEqualTo(length == 30_000);
            assertThat(result.unavailableReasons().contains("CONTINUOUS_GAP_EXCEEDED")).isEqualTo(length > 30_000);
        }
    }

    @Test void fivePercentUsesOriginalMillisecondsAndDoesNotRound() {
        for (long extra : List.of(0L, 1L)) {
            var raw = qualityRun(List.of(new long[]{100_000, 130_000}, new long[]{300_000, 330_000},
                    new long[]{500_000, 530_000}, new long[]{700_000, 710_000 + extra}));
            var result = builder.build(source(raw), snapshot(), raw);
            assertThat(result.durationMs()).isEqualTo(2_000_000L);
            assertThat(result.quality().gapMs()).isEqualTo(100_000 + extra);
            assertThat(result.eligible()).isEqualTo(extra == 0);
            assertThat(result.unavailableReasons().contains("TOTAL_GAP_EXCEEDED")).isEqualTo(extra > 0);
        }
    }

    @Test void silentTenSecondBoundaryKeepsTheExistingConnectionRule() {
        var withBoundary = qualityRun(List.of(new long[]{100_000, 110_000}));
        List<Input> exact = new ArrayList<>();
        for (Input p : withBoundary) {
            if (p.kind() != Kind.GAP)
                exact.add(input(exact.size(), p.kind(), p.elapsedMs(), p.location(), p.reason()));
        }
        var exactResult = builder.build(source(exact), snapshot(), exact);
        assertThat(exactResult.quality().gapMs()).isZero();
        var raw = qualityRun(List.of(new long[]{100_000, 110_001}));
        assertThat(builder.build(source(raw), snapshot(), raw).quality().gapMs()).isEqualTo(10_001);
    }

    @Test void missingInputsAndChangedSnapshotFailClosedWithoutRewritingTheSavedTime() {
        var raw = qualityRun(List.of());
        Result source = source(raw);
        var missing = new ArrayList<>(raw); missing.remove(3);
        assertThat(builder.build(source, snapshot(), missing).unavailableReasons()).containsExactly("MISSING_SOURCE_INPUTS");
        var changed = new CourseSnapshot(recordId, courseId, "변경", route, 1000, 4);
        assertThat(builder.build(source, changed, raw).unavailableReasons()).containsExactly("COURSE_VERSION_MISMATCH");
        assertThat(source.course().courseElapsedSeconds()).isEqualTo(2000);
    }

    @Test void aProjectedSpeedJumpIsNotExposedAsAnExactTrustedPosition() {
        var raw = new ArrayList<>(qualityRun(List.of()));
        for (int i = 0; i < raw.size(); i++) {
            Input p = raw.get(i);
            if (p.kind() == Kind.GPS && p.elapsedMs() == 100_000)
                raw.set(i, input(p.seq(), Kind.GPS, p.elapsedMs(), point(200), null));
        }
        var result = builder.build(source(raw), snapshot(), raw);
        assertThat(result.eligible()).isTrue();
        assertThat(result.samples().stream().filter(p -> p.elapsedMs() == 100_000).findFirst().orElseThrow().coursePositionM()).isNull();
        assertThat(result.spans().stream().filter(s -> s.fromMs() <= 100_000 && s.toMs() > 100_000).findFirst().orElseThrow().state())
                .isEqualTo(GhostSpanState.UNKNOWN);
    }
}
