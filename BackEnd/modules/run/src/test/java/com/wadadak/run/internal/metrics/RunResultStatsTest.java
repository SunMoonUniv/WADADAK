package com.wadadak.run.internal.metrics;

import com.wadadak.run.internal.RunContracts.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class RunResultStatsTest {
    @Test void sharedResultScenariosMatchAppWithoutChangingDistanceOrLaps() throws Exception {
        var json = JsonMapper.builder().findAndAddModules().build();
        var fixture = json.readTree(Files.readString(Path.of("../run/fixtures/free_result_stats_v2.json")));
        for (var c : fixture.get("cases")) {
            var inputs = new ArrayList<Input>();
            for (var p : c.get("inputs")) inputs.add(json.treeToValue(p, Input.class));
            var result = FreeRunCalculator.calculate(Instant.parse(c.get("startedAt").asString()), inputs);
            var actual = json.valueToTree(result.stats());
            var expected = c.get("expected");
            for (String key : new String[] {"elevationGainM","bestLapPaceSecondsPerKm","bestPaceSecondsPerKm","bestLapNumber"}) {
                if (expected.get(key).isNull()) assertThat(actual.get(key).isNull()).as(c.get("name").asString()+":"+key).isTrue();
                else assertThat(actual.get(key).asDouble()).as(c.get("name").asString()+":"+key)
                    .isCloseTo(expected.get(key).asDouble(), within(.000001));
            }
            assertThat(actual.get("elevationPartial").asBoolean()).as(c.get("name").asString()).isEqualTo(expected.get("elevationPartial").asBoolean());
            assertThat(result.stats().version()).isEqualTo(RunResultStatsCalculator.VERSION);
            var withoutAltitude = inputs.stream().map(p -> new Input(p.seq(),p.kind(),p.elapsedMs(),p.measuredAt(),p.location(),p.accuracyM(),p.reason(),p.speedMps(),p.speedAccuracyMps(),p.steps(),p.durationMs(),p.sampleEndMs())).toList();
            var original = FreeRunCalculator.calculate(Instant.parse(c.get("startedAt").asString()), withoutAltitude);
            assertThat(result.metrics()).isEqualTo(original.metrics());
            assertThat(result.laps()).isEqualTo(original.laps());
        }
    }
}
