package com.wadadak.run.internal.metrics;

import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.common.exception.AppException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class BarometerStatsTest {
    @Test void sharedBarometerScenariosMatchAppAndPreserveAllOtherMetrics() throws Exception {
        var json = JsonMapper.builder().findAndAddModules().build();
        var fixture = json.readTree(Files.readString(Path.of("../run/fixtures/free_barometer_v3.json")));
        for (var c : fixture.get("cases")) {
            var inputs = new ArrayList<Input>();
            for (var p : c.get("inputs")) inputs.add(json.treeToValue(p,Input.class));
            var start = Instant.parse(c.get("startedAt").asString());
            var result = FreeRunCalculator.calculate(start,inputs);
            var expected = c.get("expected");
            var actual = json.valueToTree(result.stats());
            for (String key : List.of("elevationGainM","elevationPartial","elevationSource")) {
                if (key.equals("elevationGainM") && !expected.get(key).isNull())
                    assertThat(actual.get(key).asDouble()).as(c.get("name").asString())
                        .isCloseTo(expected.get(key).asDouble(),within(.000001));
                else assertThat(actual.get(key)).as(c.get("name").asString()+":"+key).isEqualTo(expected.get(key));
            }
            assertThat(result.stats().version()).isEqualTo("RESULT_V3");
            var without = new ArrayList<Input>();
            for (Input p : inputs) if (p.kind()!=Kind.BAROMETER)
                without.add(new Input(without.size(),p.kind(),p.elapsedMs(),p.measuredAt(),p.location(),p.accuracyM(),p.reason(),
                    p.speedMps(),p.speedAccuracyMps(),p.steps(),p.durationMs(),p.sampleEndMs(),p.altitudeM(),p.altitudeAccuracyM()));
            var original = FreeRunCalculator.calculate(start,without);
            assertThat(result.metrics()).as(c.get("name").asString()).isEqualTo(original.metrics());
            assertThat(result.laps()).isEqualTo(original.laps());
            assertThat(result.segments()).isEqualTo(original.segments());
            assertThat(result.stats().bestPaceSecondsPerKm()).isEqualTo(original.stats().bestPaceSecondsPerKm());
            assertThat(result.stats().bestLapNumber()).isEqualTo(original.stats().bestLapNumber());
            for (Input p : inputs) assertThat(json.readValue(json.writeValueAsString(p),Input.class)).isEqualTo(p);
        }
    }

    @Test void impossibleSensorTimestampsAndMalformedPressureFailValidation() {
        Instant start = Instant.parse("2026-10-12T00:00:00Z");
        for (Input pressure : List.of(
            pressure(start,1000,2000L,1000.0,3), // future
            pressure(start,5000,1000L,1000.0,3), // stale
            pressure(start,1000,-1L,1000.0,3),
            pressure(start,1000,1000L,Double.NaN,3),
            pressure(start,1000,1000L,0.0,3),
            pressure(start,1000,1000L,1000.0,4))) {
            var inputs = List.of(new Input(0,Kind.START,0,start,null,null,"PACE_V2"),pressure,
                new Input(2,Kind.END,6000,start.plusMillis(6000),null,null,"INTERRUPTED"));
            assertThatThrownBy(() -> FreeRunCalculator.calculate(start,inputs)).isInstanceOf(AppException.class);
        }
    }
    private static Input pressure(Instant start,long ms,Long sampleMs,Double hpa,Integer accuracy) {
        return new Input(1,Kind.BAROMETER,ms,start.plusMillis(ms),null,null,null,null,null,null,null,sampleMs,null,null,hpa,accuracy);
    }
}
