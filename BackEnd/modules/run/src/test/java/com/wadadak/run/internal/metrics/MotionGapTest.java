package com.wadadak.run.internal.metrics;

import com.wadadak.run.internal.RunContracts.Input;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class MotionGapTest {
    private final JsonMapper json = JsonMapper.builder().findAndAddModules().build();

    @TestFactory List<DynamicTest> sharedGapBoundariesPreserveMeasurementRules() throws Exception {
        var fixture = json.readTree(Files.readString(Path.of("../run/fixtures/motion_gap_null_v1.json")));
        var tests = new ArrayList<DynamicTest>();
        for (var c : fixture.get("cases")) {
            tests.add(DynamicTest.dynamicTest(c.get("name").asText(), () -> {
                var raw = new ArrayList<Input>();
                for (var p : c.get("inputs")) raw.add(json.treeToValue(p, Input.class));
                String before = json.writeValueAsString(raw);
                var expected = c.get("expected");
                var actual = FreeRunCalculator.calculate(raw.getFirst().measuredAt(), raw);
                var metrics = actual.metrics();
                assertThat(metrics.distanceM()).isCloseTo(expected.get("distanceM").asDouble(), within(.000001));
                assertThat(metrics.elapsedMs()).isEqualTo(expected.get("elapsedMs").asLong());
                assertThat(metrics.activeMs()).isEqualTo(expected.get("activeMs").asLong());
                assertThat(metrics.movingMs()).isEqualTo(expected.get("movingMs").asLong());
                assertThat(metrics.gapCount()).isEqualTo(expected.get("gapCount").asInt());
                var motion = new MotionPace();
                raw.forEach(motion::add);
                var expectedMs = new ArrayList<List<Long>>();
                var expectedRoute = new ArrayList<List<com.wadadak.common.geo.GeoPoint>>();
                for (var segment : expected.get("segmentMs")) {
                    var times = new ArrayList<Long>();
                    var route = new ArrayList<com.wadadak.common.geo.GeoPoint>();
                    for (var ms : segment) {
                        times.add(ms.asLong());
                        route.add(raw.stream().filter(p -> p.elapsedMs() == ms.asLong()).findFirst().orElseThrow().location());
                    }
                    expectedMs.add(times); expectedRoute.add(route);
                }
                assertThat(motion.samples.stream().map(s -> s.stream().map(Input::elapsedMs).toList()).toList())
                    .isEqualTo(expectedMs);
                assertThat(actual.segments()).isEqualTo(expectedRoute);
                assertThat(actual.laps()).hasSize(1);
                assertThat(actual.laps().getFirst().distanceM()).isCloseTo(metrics.distanceM(), within(.000001));
                assertThat(actual.laps().getFirst().movingMs()).isEqualTo(metrics.movingMs());
                assertThat(actual.laps().getFirst().elapsedMs()).isEqualTo(metrics.elapsedMs());
                assertThat(json.writeValueAsString(raw)).isEqualTo(before);
            }));
        }
        return tests;
    }
}
