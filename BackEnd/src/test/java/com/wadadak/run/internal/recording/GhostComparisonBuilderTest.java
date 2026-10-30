package com.wadadak.run.internal.recording;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.ghost.GhostPlaybackBuilder;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class GhostComparisonBuilderTest {
    final Instant at=Instant.parse("2026-10-30T00:00:00Z");
    final UUID id=UUID.randomUUID(),source=UUID.randomUUID();
    final CourseSnapshot reference=new CourseSnapshot(id,UUID.randomUUID(),"5.2km",List.of(
        new GeoPoint(37,127),new GeoPoint(37+5200/111195.0,127)),5200,1);
    List<Input> raw(int interval) {
        var raw=new ArrayList<Input>();raw.add(new Input(0,Kind.START,0,at,null,null,null));
        for(int i=0;i<=260;i++)raw.add(new Input(raw.size(),Kind.GPS,(long)i*interval,at.plusMillis((long)i*interval),
            new GeoPoint(37+(i*20)/111195.0,127),3.0,null));
        raw.add(new Input(raw.size(),Kind.END,260L*interval+1,at.plusMillis(260L*interval+1),null,null,"INTERRUPTED"));
        return raw;
    }
    GhostPlayback replay(UUID record,List<Input> raw) {return new GhostPlaybackBuilder().comparison(record,reference,raw,false);}
    GhostOutcome outcome(GhostPlayback trace) {return new GhostOutcome("GHOST_RESULT_V1",id,source,GhostVerdict.WIN,
        GhostVerdictReason.COMPLETED_TIME_COMPARISON,true,trace.courseElapsedSeconds(),replay(source,raw(6000)).courseElapsedSeconds(),
        trace.durationMs(),replay(source,raw(6000)).durationMs(),"ROUTE_END",at.plusSeconds(9999));}
    ComparisonContext context(GhostPlayback source,Long best) {return new ComparisonContext(source,"OWN_COURSE",null,
        UUID.randomUUID(),null,true,best);}

    @Test void fivePointTwoHasFiveFullSegmentsAndIndependentTailWithConsistentTotal() {
        var raw=raw(5000);var trace=replay(id,raw);
        var d=GhostComparisonBuilder.build(context(replay(source,raw(6000)),9999L),outcome(trace),raw);
        assertThat(d.status()).isEqualTo("AVAILABLE");assertThat(d.segments()).hasSize(6);
        assertThat(d.segments().getLast().fromMeters()).isEqualTo(5000);
        assertThat(d.segments().getLast().toMeters()).isEqualTo(5200);
        assertThat(d.segments().getLast().fullKilometer()).isFalse();
        assertThat(d.segments().stream().mapToLong(ComparisonSegment::deltaSeconds).sum())
            .isEqualTo(d.result().sourceElapsedSeconds()-d.result().courseElapsedSeconds());
        assertThat(d.segments().getLast().cumulativeDeltaSeconds())
            .isEqualTo(d.result().sourceElapsedSeconds()-d.result().courseElapsedSeconds());
        assertThat(d.ours().bestSegment()).isBetween(1,5);assertThat(d.personalBest()).isEqualTo("IMPROVED");
    }
    @Test void gapsAreNotInterpolatedAndDoNotChangeTheFinalVerdict() {
        var sourceReplay=replay(source,raw(6000));
        var gaps=sourceReplay.spans().stream().map(s->new GhostSpan(s.fromMs(),s.toMs(),null,null,GhostSpanState.UNKNOWN)).toList();
        var gapped=new GhostPlayback(source,reference,sourceReplay.version(),sourceReplay.sourcePolicyVersion(),sourceReplay.sourceCalculationVersion(),
            sourceReplay.courseElapsedSeconds(),sourceReplay.durationMs(),true,List.of(),sourceReplay.quality(),sourceReplay.samples(),gaps);
        var raw=raw(5000);var result=outcome(replay(id,raw));
        var d=GhostComparisonBuilder.build(context(gapped,null),result,raw);
        assertThat(d.result()).isEqualTo(result);
        assertThat(d.segments()).allSatisfy(s->{assertThat(s.deltaSeconds()).isNull();assertThat(s.cumulativeDeltaSeconds()).isNull();});
    }
    @Test void personalBestIsIndependentOfDuelWinAndStrictlyFaster() {
        var raw=raw(5000);var result=outcome(replay(id,raw));
        var d=GhostComparisonBuilder.build(context(replay(source,raw(6000)),result.courseElapsedSeconds()),result,raw);
        assertThat(d.result().outcome()).isEqualTo(GhostVerdict.WIN);assertThat(d.personalBest()).isEqualTo("UNCHANGED");
    }
    @Test void changedHistoricalResultGetsReasonWithoutChangingSummary() {
        var raw=raw(5000);var original=outcome(replay(id,raw));
        var changed=new GhostOutcome(original.version(),id,source,original.outcome(),original.reason(),true,
            original.courseElapsedSeconds()+1,original.sourceElapsedSeconds(),original.courseEndElapsedMs(),original.sourceDurationMs(),original.courseEndReason(),original.finalizedAt());
        var d=GhostComparisonBuilder.build(context(replay(source,raw(6000)),null),changed,raw);
        assertThat(d.status()).isEqualTo("SOURCE_RESULT_MISMATCH");assertThat(d.result()).isEqualTo(changed);
        assertThat(d.segments()).isEmpty();
    }
    @Test void activeAndCadenceNeverIncludeFollowingFreeRunOrPartialSensorWindows() {
        var raw=List.of(new Input(0,Kind.START,0,at,null,null,null),
            new Input(1,Kind.CADENCE,10000,at.plusSeconds(10),null,null,null,null,null,20,10000L,10000L,null,null),
            new Input(2,Kind.PAUSE,10000,at.plusSeconds(10),null,null,null),
            new Input(3,Kind.RESUME,20000,at.plusSeconds(20),null,null,"MANUAL"),
            new Input(4,Kind.CADENCE,30000,at.plusSeconds(30),null,null,null,null,null,30,10000L,30000L,null,null),
            new Input(5,Kind.CADENCE,40000,at.plusSeconds(40),null,null,null,null,null,40,10000L,40000L,null,null));
        assertThat(GhostComparisonBuilder.activeMs(raw,30000)).isEqualTo(20000);
        assertThat(GhostComparisonBuilder.cadence(raw,30000)).isEqualTo(150);
        assertThat(GhostComparisonBuilder.cadence(raw,25000)).isEqualTo(120);
    }

    @Test void bestSegmentUsesMillisecondsAndEarliestOnlyForAnExactTie() {
        var one=new ComparisonSegment(1,0,1000,true,1L,1L,0L,0L,null,1900L,1900L,0L,0L);
        var two=new ComparisonSegment(2,1000,2000,true,1L,1L,0L,0L,null,1100L,1100L,0L,0L);
        var three=new ComparisonSegment(3,2000,3000,true,1L,1L,0L,0L,null,1100L,1100L,0L,0L);
        var partial=new ComparisonSegment(4,3000,3200,false,0L,0L,0L,0L,null,100L,100L,0L,0L);
        assertThat(GhostComparisonBuilder.best(List.of(one,two,three,partial),true)).isEqualTo(2);
    }
}
