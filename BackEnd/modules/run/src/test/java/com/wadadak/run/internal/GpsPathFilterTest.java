package com.wadadak.run.internal;

import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.ghost.GhostPlaybackBuilder;
import com.wadadak.run.internal.metrics.FreeRunCalculator;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class GpsPathFilterTest {
    final JsonMapper json=JsonMapper.builder().findAndAddModules().build();
    List<JsonNode> cases() throws Exception {
        var values=json.readTree(Files.readString(Path.of("../run/fixtures/gps_path_v4.json"))).get("cases");
        var out=new ArrayList<JsonNode>(); values.forEach(out::add); return out;
    }
    List<Input> raw(JsonNode c) {
        var out=new ArrayList<Input>();
        c.get("inputs").forEach(p->out.add(json.treeToValue(p,Input.class))); return out;
    }
    @Test void sharedScenariosPreserveRawDataTimeSensorsAndBoundaries() throws Exception {
        for(var c:cases()) {
            var inputs=raw(c);var before=json.writeValueAsString(inputs);
            var filtered=GpsPathFilter.normalize(inputs);
            assertThat(filtered).as(c.get("name").asText()).hasSameSizeAs(inputs);
            for(int i=0;i<inputs.size();i++) {
                var a=inputs.get(i);var b=filtered.get(i);
                assertThat(a.seq()).isEqualTo(b.seq());
                assertThat(a.elapsedMs()).isEqualTo(b.elapsedMs());
                assertThat(a.measuredAt()).isEqualTo(b.measuredAt());
                assertThat(a.kind()).isEqualTo(b.kind());
                assertThat(a.speedMps()).isEqualTo(b.speedMps());
                if(a.kind()!=Kind.GPS) assertThat(b).isEqualTo(a);
            }
            assertThat(json.writeValueAsString(inputs)).isEqualTo(before);
            var gps=filtered.stream().filter(p->p.kind()==Kind.GPS).toList();
            switch(c.get("behavior").asText()) {
                case "stationary" -> {
                    for(var p:gps)assertThat(p.location().distanceMeters(gps.getFirst().location())).isLessThan(1e-6);
                }
                case "unchanged" -> assertThat(filtered).as(c.get("name").asText()).isEqualTo(inputs);
                case "spike" -> assertThat(gps.get(10).location().lat()).isCloseTo(37,within(1e-9));
                case "smoother" -> {
                    double original=0,clean=0;
                    var rawGps=inputs.stream().filter(p->p.kind()==Kind.GPS).toList();
                    for(int i=1;i<gps.size();i++){
                        original+=rawGps.get(i-1).location().distanceMeters(rawGps.get(i).location());
                        clean+=gps.get(i-1).location().distanceMeters(gps.get(i).location());
                    }
                    assertThat(clean).isLessThan(original*.98);
                }
            }
        }
    }
    @Test void stoppedJitterRemainsReplayableButRealOutageIsRejected() throws Exception {
        for(var c:cases()) {
            String behavior=c.get("behavior").asText();
            if(!behavior.startsWith("long"))continue;
            var inputs=raw(c);var calc=FreeRunCalculator.calculate(inputs.getFirst().measuredAt(),inputs);
            var points=new ArrayList<com.wadadak.common.geo.GeoPoint>();
            var breaks=new ArrayList<Integer>();
            for(var segment:calc.samples()) {
                if(segment.size()<2)continue;
                if(!points.isEmpty())breaks.add(points.size());
                segment.forEach(p->points.add(p.location()));
            }
            UUID id=UUID.randomUUID();var at=inputs.getFirst().measuredAt();
            var source=new Result(id,at,calc.endedAt(),at.plusSeconds(90000),"USER",calc.metrics(),calc.segments(),calc.laps(),"2026-10-14","PACE_V4",calc.stats(),null);
            var snapshot=new CourseSnapshot(id,null,"test",points,(int)Math.ceil(calc.metrics().distanceM()),1,breaks);
            var built=new GhostPlaybackBuilder().buildReferenceWithJudgement(source,snapshot,inputs,GhostPlaybackBuilder.FREE_VERSION_V2);
            assertThat(built.judgement().completed()).as(c.get("name").asText()).isTrue();
            var replay=built.playback();
            if(behavior.equals("long")) {
                assertThat(calc.metrics().distanceM()).isBetween(1240.0,1280.0);
                assertThat(replay.eligible()).as(replay.unavailableReasons().toString()).isTrue();
                assertThat(replay.quality().maxGapMs()).isLessThanOrEqualTo(30_000);
                assertThat(calc.metrics().movingMs()).isLessThan(calc.metrics().activeMs()-100_000);
            } else {
                assertThat(replay.eligible()).isFalse();
                assertThat(replay.unavailableReasons()).contains("CONTINUOUS_GAP_EXCEEDED");
            }
        }
    }

    @Test void exportSharedScenarioMetricsForAppServerParity() throws Exception {
        var report=new ArrayList<Map<String,Object>>();
        for(var c:cases()) {
            var inputs=raw(c);
            var calc=FreeRunCalculator.calculate(inputs.getFirst().measuredAt(),inputs);
            report.add(Map.of("name",c.get("name").asText(),"inputs",GpsPathFilter.normalize(inputs),
                    "distanceM",calc.metrics().distanceM(),"movingMs",calc.metrics().movingMs(),
                    "elapsedMs",calc.metrics().elapsedMs()));
        }
        Files.createDirectories(Path.of("build"));
        Files.writeString(Path.of("build/gps-path-v4-parity.json"),json.writeValueAsString(report));
    }
}
