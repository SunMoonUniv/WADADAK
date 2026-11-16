package com.wadadak.run.internal.recording;

import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.ghost.GhostPlaybackBuilder;
import java.util.ArrayList;
import java.util.List;

/** Display-only derivation from the frozen replay and the runner's unchanged inputs/verdict. */
final class GhostComparisonBuilder {
    static final String VERSION = "GHOST_COMPARISON_V1";
    private static final double EPS = 1e-6;
    private GhostComparisonBuilder() {}

    static GhostComparison build(ComparisonContext context, GhostOutcome result, List<Input> inputs) {
        var source=context.playback();
        var reference=source.course();
        boolean freeV2="GHOST_PLAYBACK_FREE_V2".equals(source.version());
        var trace=new GhostPlaybackBuilder().comparison(result.sessionId(),reference,inputs,freeV2);
        // A different historical calculation must never silently change a saved verdict.
        if(trace.courseElapsedSeconds()!=result.courseElapsedSeconds()) return unavailable(result,"SOURCE_RESULT_MISMATCH");
        long end=trace.durationMs(), otherEnd=source.durationMs();
        int distance=reference.totalDistanceMeters();
        var segments=new ArrayList<ComparisonSegment>();
        for(int number=1; (number-1)*1000.0<distance-EPS; number++) {
            double from=(number-1)*1000.0, to=Math.min(number*1000.0,distance);
            Long ourFrom=arrival(trace,from), ghostFrom=arrival(source,from);
            Long ourTo=to==distance && result.completed()?Long.valueOf(end):arrival(trace,to);
            Long ghostTo=to==distance?Long.valueOf(otherEnd):arrival(source,to);
            boolean ourMissing=ourFrom==null||ourTo==null, ghostMissing=ghostFrom==null||ghostTo==null;
            boolean ourGap=!ourMissing&&hasUnknown(trace,ourFrom,ourTo), ghostGap=!ghostMissing&&hasUnknown(source,ghostFrom,ghostTo);
            String reason=ourMissing||ghostMissing?"POSITION_UNCONFIRMED":ourGap||ghostGap?"GPS_GAP":null;
            Long ours=ourMissing||ourGap?null:ourTo/1000-ourFrom/1000;
            Long theirs=ghostMissing||ghostGap?null:ghostTo/1000-ghostFrom/1000;
            Long cumulative=reason==null?ghostTo/1000-ourTo/1000:null;
            // End label uses the immutable server seconds, never a separate rounded verdict.
            if(to==distance && result.completed() && reason==null) cumulative=result.sourceElapsedSeconds()-result.courseElapsedSeconds();
            segments.add(new ComparisonSegment(number,from,to,Math.abs(to-from-1000)<EPS,ours,theirs,
                    reason==null?theirs-ours:null,cumulative,reason,
                    ourMissing||ourGap?null:ourTo-ourFrom,ghostMissing||ghostGap?null:ghostTo-ghostFrom,
                    reason==null?(ghostTo-ghostFrom)-(ourTo-ourFrom):null,reason==null?ghostTo-ourTo:null));
        }
        Integer ourBest=best(segments,true), ghostBest=best(segments,false);
        var ours=new ComparisonMetrics(result.completed()?result.courseElapsedSeconds():null,
                activeMs(inputs,end),result.completed()?result.courseElapsedSeconds()*1000.0/distance:null,
                cadence(inputs,end),ourBest);
        var previous=context.metrics();
        var ghost=new ComparisonMetrics(result.sourceElapsedSeconds(),previous==null?null:previous.activeMs(),
                result.sourceElapsedSeconds()*1000.0/distance,previous==null?null:previous.averageCadence(),ghostBest);
        String pb=!result.completed()?"NOT_COMPLETED":reference.courseId()==null?"NOT_APPLICABLE":
                !context.baselineKnown()?"UNVERIFIED":context.previousBestSeconds()==null?"FIRST_COMPLETION":
                result.courseElapsedSeconds()<context.previousBestSeconds()?"IMPROVED":"UNCHANGED";
        double reached=trace.samples().stream().filter(p->p.coursePositionM()!=null)
                .mapToDouble(GhostSample::coursePositionM).max().orElse(0);
        return new GhostComparison(VERSION,result.sessionId(),result.sourceRecordId(),result,"AVAILABLE",
                reference.courseId(),reference.name(),distance,context.kind(),context.publicPeriod(),"AVAILABLE",reached,pb,
                context.previousBestSeconds(),ours,ghost,List.copyOf(segments));
    }

    static GhostComparison unavailable(GhostOutcome result,String reason) {
        return new GhostComparison(VERSION,result.sessionId(),result.sourceRecordId(),result,reason,null,null,0,
                "UNKNOWN",null,"UNKNOWN",0,"UNVERIFIED",null,null,null,List.of());
    }

    static Long arrival(GhostPlayback replay,double position) {
        if(position==0) return 0L; // Waiting after measurement START belongs to the first segment.
        Long first=null;
        for(var span:replay.spans()) {
            if(span.state()!=GhostSpanState.TRACKED || span.fromPositionM()==null || span.toPositionM()==null
                    || span.toPositionM()<=span.fromPositionM() || position<span.fromPositionM()-EPS
                    || position>span.toPositionM()+EPS) continue;
            long ms=Math.round(span.fromMs()+(span.toMs()-span.fromMs())*
                    Math.clamp((position-span.fromPositionM())/(span.toPositionM()-span.fromPositionM()),0,1));
            if(first==null||ms<first) first=ms;
        }
        return first;
    }
    private static boolean hasUnknown(GhostPlayback replay,long from,long to) {
        return replay.spans().stream().anyMatch(s->s.state()==GhostSpanState.UNKNOWN && s.fromMs()<to && s.toMs()>from);
    }
    static Integer best(List<ComparisonSegment> segments,boolean ours) {
        ComparisonSegment best=null;
        for(var s:segments) {
            Long ms=ours?s.ourMs():s.ghostMs();
            if(!s.fullKilometer()||ms==null)continue;
            if(best==null||ms<(ours?best.ourMs():best.ghostMs()))best=s;
        }
        return best==null?null:best.number();
    }
    static long activeMs(List<Input> inputs,long end) {
        long paused=0;Long since=null;
        for(var p:inputs) {
            if(p.elapsedMs()>end)break;
            if(p.kind()==Kind.PAUSE&&since==null)since=p.elapsedMs();
            if(p.kind()==Kind.RESUME&&since!=null){paused+=p.elapsedMs()-since;since=null;}
        }
        if(since!=null)paused+=end-since;
        return Math.max(0,end-paused);
    }
    static Double cadence(List<Input> inputs,long end) {
        long steps=0,coverage=0,lastResume=0,lastSample=0;boolean paused=false;
        for(var p:inputs) {
            if(p.kind()==Kind.PAUSE)paused=true;
            if(p.kind()==Kind.RESUME){paused=false;lastResume=p.elapsedMs();}
            if(p.kind()!=Kind.CADENCE||paused||p.steps()==null||p.durationMs()==null||p.durationMs()<=0)continue;
            long to=p.sampleEndMs()==null?p.elapsedMs():p.sampleEndMs(),from=to-p.durationMs();
            if(to>end||from<Math.max(lastResume,lastSample))continue;
            steps+=p.steps();coverage+=p.durationMs();lastSample=to;
        }
        return coverage==0?null:steps*60000.0/coverage;
    }
}

record SourceComparisonMetrics(long activeMs,Double averageCadence) {}
record ComparisonContext(com.wadadak.run.internal.RunContracts.GhostPlayback playback,
        String kind, String publicPeriod, java.util.UUID sourceOwner, SourceComparisonMetrics metrics,
        boolean baselineKnown,Long previousBestSeconds) {}
