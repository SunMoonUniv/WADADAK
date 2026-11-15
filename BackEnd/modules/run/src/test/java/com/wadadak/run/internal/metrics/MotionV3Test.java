package com.wadadak.run.internal.metrics;

import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.RunContracts.Kind;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class MotionV3Test {
    private final JsonMapper mapper = JsonMapper.builder().findAndAddModules().build();
    private List<Input> inputs(JsonNode values) {
        List<Input> result = new ArrayList<>();
        for (var value : values) result.add(mapper.treeToValue(value,Input.class));
        return result;
    }
    @Test void sharedBalancedScenariosPreserveTurnsAndRejectIsolatedFixes() throws Exception {
        var fixture = mapper.readTree(Files.readString(Path.of("../run/fixtures/free_motion_v3.json")));
        for (var c : fixture.get("cases")) {
            var raw = inputs(c.get("inputs"));
            var result = FreeRunCalculator.calculate(raw.getFirst().measuredAt(),raw);
            var referenceInputs = inputs(c.get("reference"));
            var reference = FreeRunCalculator.calculate(referenceInputs.getFirst().measuredAt(),referenceInputs);
            assertThat(result.metrics().distanceM()).as(c.get("name").asText()).isCloseTo(reference.metrics().distanceM(),within(.000001));
            assertThat(result.metrics().movingMs()).as(c.get("name").asText()).isEqualTo(reference.metrics().movingMs());
            assertThat(result.segments()).as(c.get("name").asText()).isEqualTo(reference.segments());
            assertThat(result.stats().elevationGainM()).isEqualTo(reference.stats().elevationGainM());
            MotionPace motion = new MotionPace();
            for (Input p : raw) motion.add(p);
            var gps = raw.stream().filter(p -> p.kind() == Kind.GPS).toList();
            for (int i=1; i<gps.size(); i++) {
                Input a=gps.get(i-1), b=gps.get(i);
                long dt=b.elapsedMs()-a.elapsedMs();
                if (dt>0 && (dt>10000 || FreeRunCalculator.distance(a.location(),b.location())*1000/dt>12)) {
                    assertThat(motion.samples.stream().anyMatch(s ->
                        s.getFirst().elapsedMs()<=a.elapsedMs() && s.getLast().elapsedMs()>=b.elapsedMs()))
                        .as("raw GPS boundary %s..%s in %s",a.elapsedMs(),b.elapsedMs(),c.get("name").asText()).isFalse();
                }
            }
        }
    }
}
