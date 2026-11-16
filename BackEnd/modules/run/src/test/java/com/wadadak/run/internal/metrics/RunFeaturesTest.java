package com.wadadak.run.internal.metrics;

import com.wadadak.run.internal.RunContracts.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class RunFeaturesTest {
    @Test void sharedFixtureMatchesAppLapAndCadenceCalculation() throws Exception {
        var json=JsonMapper.builder().findAndAddModules().build();
        var fixture=json.readTree(Files.readString(Path.of("../run/fixtures/free_features_v3.json")));
        var inputs=new ArrayList<Input>();
        for(var node:fixture.get("inputs")) inputs.add(json.treeToValue(node,Input.class));
        var result=FreeRunCalculator.calculate(Instant.parse(fixture.get("startedAt").asString()),inputs);
        assertThat(result.metrics().distanceM()).isCloseTo(2550,within(.000001));
        assertThat(result.metrics().activeMs()).isEqualTo(541000);
        assertThat(result.metrics().movingMs()).isEqualTo(541000);
        assertThat(result.metrics().averageCadence()).isEqualTo(180);
        assertThat(result.metrics().cadenceCoverageMs()).isEqualTo(510000);
        assertThat(result.metrics().steps()).isEqualTo(1530);
        assertThat(result.laps()).hasSize(3);
        assertThat(result.laps().stream().map(Lap::movingMs)).containsExactly(200000L,200000L,141000L);
        assertThat(result.laps().stream().map(Lap::elapsedMs)).containsExactly(200000L,230000L,150000L);
        assertThat(result.laps().getLast().distanceM()).isCloseTo(550,within(.000001));
        assertThat(result.laps().getLast().complete()).isFalse();
        var withoutSensor=inputs.stream().filter(p->p.kind()!=Kind.CADENCE).toList();
        var renumbered=new ArrayList<Input>();
        for(Input p:withoutSensor) renumbered.add(new Input(renumbered.size(),p.kind(),p.elapsedMs(),p.measuredAt(),p.location(),p.accuracyM(),p.reason(),p.speedMps(),p.speedAccuracyMps()));
        assertThat(FreeRunCalculator.calculate(Instant.parse(fixture.get("startedAt").asString()),renumbered).metrics().distanceM())
            .isCloseTo(result.metrics().distanceM(),within(.000001));
    }
}
