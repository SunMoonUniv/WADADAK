package com.wadadak.run.internal;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.RunContracts.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class FreeRunCalculatorTest {
    final Instant start=Instant.parse("2026-10-12T00:00:00Z");
    Input point(int seq,Kind kind,long ms,Double lat,double accuracy) {
        return new Input(seq,kind,ms,start.plusMillis(ms),lat==null?null:new GeoPoint(lat,127),lat==null?null:accuracy,kind==Kind.END?"USER":null);
    }
    @Test void sharedFixtureMatchesApp() throws Exception {
        var mapper=JsonMapper.builder().findAndAddModules().build();
        var fixture=mapper.readTree(Files.readString(Path.of("../run/fixtures/free_pause_v1.json")));
        List<Input> inputs=new ArrayList<>();
        for(var node:fixture.get("inputs")) inputs.add(mapper.treeToValue(node,Input.class));
        var result=FreeRunCalculator.calculate(start,inputs).metrics();
        assertThat(result.elapsedMs()).isEqualTo(120000);
        assertThat(result.activeMs()).isEqualTo(100000);
        assertThat(result.distanceM()).isCloseTo(22.239016,within(0.000001));
        assertThat(result.elapsedPaceSecondsPerKm()).isCloseTo(120000/result.distanceM(),within(0.000001));
        assertThat(result.paceSecondsPerKm()).isCloseTo(100000/result.distanceM(),within(0.000001));
    }
    @Test void v2SharedFixtureExcludesRestAndJitterButPreservesRankingTime() throws Exception {
        var mapper=JsonMapper.builder().findAndAddModules().build();
        var fixture=mapper.readTree(Files.readString(Path.of("../run/fixtures/free_motion_v2.json")));
        List<Input> inputs=new ArrayList<>();
        for(var node:fixture.get("inputs")) inputs.add(mapper.treeToValue(node,Input.class));
        var result=FreeRunCalculator.calculate(Instant.parse("2026-10-14T00:00:00Z"),inputs).metrics();
        assertThat(result.distanceM()).isCloseTo(30,within(.001));
        assertThat(result.movingMs()).isEqualTo(10000);
        assertThat(result.activeMs()).isEqualTo(30000);
        assertThat(result.elapsedMs()).isEqualTo(30000);
        assertThat(result.paceSecondsPerKm()).isCloseTo(1000.0/3,within(.01));
        assertThat(result.elapsedPaceSecondsPerKm()).isCloseTo(1000,within(.01));
    }
    @Test void v2ReliableStationarySpeedDoesNotTurnGpsDriftIntoDistance() {
        MotionPace motion = new MotionPace();
        motion.add(new Input(0,Kind.START,0,start,null,null,"PACE_V2"));
        for(int i=0;i<=30;i++) {
            motion.add(new Input(i+1,Kind.GPS,i*1000,start.plusMillis(i*1000),
                new GeoPoint(36+i*.8/111195.0802335,127),3.0,null,0.0,.1));
        }
        assertThat(motion.distanceM).isZero();
    }
    @Test void v2SlowDepartureWithoutSpeedMetadataAndTurnsArePreserved() {
        MotionPace motion = new MotionPace();
        for(int i=0;i<=10;i++) motion.add(point(i,Kind.GPS,i*1000,36.0,3));
        for(int i=11;i<=30;i++) motion.add(point(i,Kind.GPS,i*1000,36+(i-10)*.6/111195.0802335,3));
        assertThat(motion.distanceM).isCloseTo(12,within(.001));
        assertThat(motion.movingMs(30000,30000)).isEqualTo(20000);
        MotionPace turn = new MotionPace();
        for(int i=0;i<=2;i++) turn.add(new Input(i,Kind.GPS,i*1000,start.plusMillis(i*1000),
            new GeoPoint(36+(i==1?3:0)/111195.0802335,127),3.0,null,3.0,.1));
        assertThat(turn.distanceM).isCloseTo(6,within(.001));
    }
    @Test void gapsAndPausedMovementDoNotBridge() {
        var result=FreeRunCalculator.calculate(start,List.of(
            point(0,Kind.START,0,null,0),point(1,Kind.GPS,0,36.0,3),point(2,Kind.GPS,1000,36.00005,3),
            point(3,Kind.GPS,2000,37.0,100),point(4,Kind.GPS,3000,36.1,3),
            point(5,Kind.GPS,14001,36.2,3),point(6,Kind.GPS,15001,37.0,3),
            point(7,Kind.PAUSE,16000,null,0),point(8,Kind.GPS,17000,38.0,3),
            point(9,Kind.RESUME,18000,null,0),point(10,Kind.GPS,18000,39.0,3),
            point(11,Kind.GPS,19000,39.00005,3),point(12,Kind.PAUSE,20000,null,0),point(13,Kind.END,20000,null,0)));
        assertThat(result.metrics().distanceM()).isCloseTo(11.119508,within(0.00001));
        assertThat(result.metrics().activeMs()).isEqualTo(18000);
        assertThat(result.metrics().gapCount()).isEqualTo(3);
    }
    @Test void rejectsMissingSequenceOrImpossibleState() {
        assertThatThrownBy(()->FreeRunCalculator.calculate(start,List.of(point(0,Kind.START,0,null,0),point(2,Kind.END,1000,null,0)))).isInstanceOf(AppException.class);
        assertThatThrownBy(()->FreeRunCalculator.calculate(start,List.of(point(0,Kind.START,0,null,0),point(1,Kind.RESUME,1000,null,0),point(2,Kind.END,2000,null,0)))).isInstanceOf(AppException.class);
    }
    @Test void interruptedRecordEndsAtSavedTime() {
        var end=new Input(2,Kind.END,5000,start.plusMillis(5000),null,null,"INTERRUPTED");
        var result=FreeRunCalculator.calculate(start,List.of(point(0,Kind.START,0,null,0),point(1,Kind.GPS,1000,36.0,3),end));
        assertThat(result.metrics().elapsedMs()).isEqualTo(5000);
        assertThat(result.metrics().activeMs()).isEqualTo(5000);
        assertThat(result.metrics().paceSecondsPerKm()).isNull();
    }
    @Test void gpsMeasurementTimeCanDifferFromArrivalWithinExistingFreshnessBounds() {
        List<Input> inputs=List.of(point(0,Kind.START,0,null,0),
            new Input(1,Kind.GPS,5000,start.plusSeconds(1),new GeoPoint(36,127),3.0,null),
            point(2,Kind.PAUSE,6000,null,0),point(3,Kind.END,7000,null,0));
        assertThat(FreeRunCalculator.calculate(start,inputs).metrics().elapsedMs()).isEqualTo(7000);
        List<Input> stale=List.of(point(0,Kind.START,0,null,0),
            new Input(1,Kind.GPS,15000,start,new GeoPoint(36,127),3.0,null),
            point(2,Kind.PAUSE,16000,null,0),point(3,Kind.END,17000,null,0));
        assertThatThrownBy(()->FreeRunCalculator.calculate(start,stale)).isInstanceOf(AppException.class);
    }

    @Test void optionalRawAltitudePreservesLegacyAndV2Calculations() throws Exception {
        var mapper=JsonMapper.builder().findAndAddModules().build();
        for(String name:List.of("free_pause_v1", "free_motion_v2")) {
            var fixture=mapper.readTree(Files.readString(Path.of("../run/fixtures/"+name+".json")));
            List<Input> original=new ArrayList<>(), elevated=new ArrayList<>();
            for(var node:fixture.get("inputs")) {
                Input p=mapper.treeToValue(node,Input.class);
                original.add(p);
                elevated.add(p.kind()==Kind.GPS ? new Input(p.seq(),p.kind(),p.elapsedMs(),p.measuredAt(),
                    p.location(),p.accuracyM(),p.reason(),p.speedMps(),p.speedAccuracyMps(),
                    p.steps(),p.durationMs(),p.sampleEndMs(),p.seq()%2==0?-3.25:0.0,0.0) : p);
            }
            Instant started=Instant.parse(fixture.get("startedAt").asString());
            var withAltitude = FreeRunCalculator.calculate(started,elevated);
            var withoutAltitude = FreeRunCalculator.calculate(started,original);
            assertThat(withAltitude.metrics()).isEqualTo(withoutAltitude.metrics());
            assertThat(withAltitude.segments()).isEqualTo(withoutAltitude.segments());
            assertThat(withAltitude.laps()).isEqualTo(withoutAltitude.laps());
            assertThat(withAltitude.endedAt()).isEqualTo(withoutAltitude.endedAt());
            assertThat(withAltitude.endReason()).isEqualTo(withoutAltitude.endReason());
            assertThat(original.stream().allMatch(p->p.altitudeM()==null)).isTrue();
        }
    }

}
