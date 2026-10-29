package com.wadadak.run.internal.judging;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.RunContracts.Input;
import java.nio.file.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class FreeGhostTrackerV2Test {
    final JsonMapper json=JsonMapper.builder().findAndAddModules().build();
    @Test void sharedFixturesCoverOrderAmbiguityBoundariesAndOriginalPolicy()throws Exception {
        var root=json.readTree(Files.readString(Path.of("../run/fixtures/free_ghost_tracker_v2.json")));
        for(var c:root.get("cases")) {
            var route=Arrays.asList(json.treeToValue(c.get("route"),GeoPoint[].class));
            var inputs=Arrays.asList(json.treeToValue(c.get("inputs"),Input[].class));
            var result=CourseJudge.freeGhostV2().analyze(route,List.of(),inputs);var j=result.judgement();
            String name=c.get("name").asText();
            assertThat(j.completed()).as(name).isEqualTo(c.get("completed").asBoolean());
            assertThat(j.recognizedM()).as(name).isBetween(c.get("minRecognizedM").asDouble(),c.get("maxRecognizedM").asDouble());
            assertThat(j.reason().name()).as(name).isEqualTo(c.get("expectedReason").asText());
            assertThat(result.courseElapsedMs()).as(name).isEqualTo(c.get("expectedElapsedMs").asLong());
            var expected=Arrays.asList(json.treeToValue(c.get("expectedSamples"),CourseJudge.CourseSample[].class));
            assertThat(result.samples()).as(name).hasSameSizeAs(expected);
            for(int i=0;i<expected.size();i++) {
                var a=result.samples().get(i);var e=expected.get(i);
                assertThat(a.seq()).as(name+" seq "+i).isEqualTo(e.seq());
                assertThat(a.elapsedMs()).isEqualTo(e.elapsedMs());
                assertThat(a.connected()).as(name+" connected "+i).isEqualTo(e.connected());
                assertThat(a.ambiguous()).isEqualTo(e.ambiguous());
                if(e.positionM()==null)assertThat(a.positionM()).as(name+" position "+i).isNull();
                else assertThat(a.positionM()).as(name+" position "+i).isCloseTo(e.positionM(),within(1e-6));
            }
        }
    }
}
