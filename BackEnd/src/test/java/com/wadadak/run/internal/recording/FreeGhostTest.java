package com.wadadak.run.internal.recording;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseApi;
import com.wadadak.event.run.CourseRunStartedEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.run.internal.RunContracts.*;
import java.time.Instant;
import java.util.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import tools.jackson.databind.json.JsonMapper;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.modulith.test.AssertablePublishedEvents;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class FreeGhostTest {
    @org.springframework.test.context.bean.override.mockito.MockitoBean com.wadadak.ranking.RankingApi rankingApi;
    @Autowired RunService runs;
    @Autowired FreeGhostService free;
    @Autowired GhostStartService starts;
    @Autowired GhostResultService results;
    @Autowired JdbcTemplate db;
    @Autowired MockMvc mvc;
    @Autowired JsonMapper json;
    @MockitoBean CourseApi courseApi;
    @MockitoBean RunProcessingWorker processing;
    @MockitoBean CourseRunReleaseWorker release;
    @MockitoBean GpsGapWorker gpsGaps;
    UUID owner,source,id;
    final Instant original=Instant.parse("2026-10-20T01:00:00Z"), now=Instant.parse("2026-10-26T01:00:00Z");
    @BeforeEach void setup() {
        for(String table:List.of("course_attempts","records","inputs","sessions","deleted_records","withdrawn_members"))
            db.update("DELETE FROM run."+table);
        owner=UUID.randomUUID();source=UUID.randomUUID();id=UUID.randomUUID();
    }
    List<Input> raw(Instant at,int count,double distance,long interval,String end,Set<Integer> missing,long extra) {
        List<Input> raw=new ArrayList<>();
        raw.add(new Input(0,Kind.START,0,at,null,null,"PACE_V1"));
        for(int i=0;i<=count;i++) {
            if(missing.contains(i)) continue;
            long ms=i*interval+(i>100?extra:0);
            var p=new GeoPoint(37+Math.toDegrees((distance*i/count)/GeoPoint.EARTH_RADIUS_M),127);
            raw.add(new Input(raw.size(),Kind.GPS,ms,at.plusMillis(ms),p,3.0,null));
        }
        long endMs=count*interval+extra+1000;
        if("USER".equals(end)) raw.add(new Input(raw.size(),Kind.PAUSE,endMs,at.plusMillis(endMs),null,null,null));
        raw.add(new Input(raw.size(),Kind.END,endMs+1000,at.plusMillis(endMs+1000),null,null,end));
        return raw;
    }
    void upload(UUID record,Instant at,List<Input> raw) {
        runs.prepare(owner,record,new Prepare(at,"FREE"));runs.upload(owner,record,new Upload(raw.size()-1,raw));runs.process(record);
    }
    GhostStart request(FreeGhostPreparation p) {return new GhostStart(null,1L,source,now,"GHOST_PLAYBACK_FREE_V1",p.referenceHash());}

    @Test void interruptedSourceStartsWithoutCourseAndSavesAWinAndSurvivesSourceDeletion(AssertablePublishedEvents events) {
        upload(source,original,raw(original,220,1200,2000,"INTERRUPTED",Set.of(),0));
        var p=free.prepare(owner,source);
        assertThat(p.playback().eligible()).as(p.playback().unavailableReasons().toString()).isTrue();
        assertThat(p.endReason()).isEqualTo("INTERRUPTED");
        assertThat(p.playback().course().courseId()).isNull();
        assertThat(p.originalElapsedMs()).isGreaterThan(p.playback().durationMs());
        var request=request(p);
        var approval=starts.start(owner,id,request);
        assertThat(starts.start(owner,id,request)).isEqualTo(approval);
        assertThat(free.receipt(owner,id)).contains(approval);
        assertThat(db.queryForObject("SELECT count(*) FROM run.course_attempts",Long.class)).isZero();
        runs.delete(owner,source);
        assertThat(starts.start(owner,id,request)).isEqualTo(approval);
        upload(id,now,raw(now,220,1200,1000,"INTERRUPTED",Set.of(),0));
        var result=runs.result(owner,id);
        assertThat(result.course()).isNull();
        assertThat(result.ghost().completed()).isTrue();
        assertThat(result.ghost().outcome()).isEqualTo(GhostVerdict.WIN);
        assertThat(results.get(owner,id)).isEqualTo(result.ghost());
        assertThat(events.ofType(CourseRunStartedEvent.class)).isEmpty();
        assertThat(events.ofType(RunSessionEndedEvent.class).matching(e->e.runRecordId().equals(id)))
            .allMatch(e->e.courseId()==null && !e.completed());
        verifyNoInteractions(courseApi);
        runs.delete(owner,id);
        assertThat(db.queryForObject("SELECT count(*) FROM run.free_ghost_results",Long.class)).isZero();
        assertThat(free.candidates(owner,OwnGhostPeriod.ALL,20,null).content()).isEmpty();
    }

    @Test void distanceIsUnroundedAndInterruptedIsNotARejectionReason() {
        upload(source,original,raw(original,220,999.9,2000,"INTERRUPTED",Set.of(),0));
        var small=free.prepare(owner,source);
        assertThat(small.playback().unavailableReasons()).contains("DISTANCE_BELOW_1000M");
        assertThat(free.candidates(owner,OwnGhostPeriod.ALL,20,null).content().getFirst().distanceEligible()).isFalse();
        assertThatThrownBy(()->starts.start(owner,id,request(small))).isInstanceOf(AppException.class);
        UUID enough=UUID.randomUUID();
        upload(enough,original.plusSeconds(1000),raw(original.plusSeconds(1000),220,1000.1,2000,"PERMISSION_REVOKED",Set.of(),0));
        var allowed=free.prepare(owner,enough);
        assertThat(allowed.playback().eligible()).as(allowed.playback().unavailableReasons().toString()).isTrue();
        assertThat(allowed.originalDistanceM()).isBetween(1000.0,1001.0);
        assertThatThrownBy(()->free.prepare(UUID.randomUUID(),enough)).isInstanceOf(AppException.class);
    }

    @Test void rejectedOverlappingFreePathExplainsRecognizedDistanceWithoutChangingPlayback() throws Exception {
        var raw=new ArrayList<>(raw(original,1200,1200,1000,"USER",Set.of(),0));
        // Synthetic nearby outbound/return legs with deterministic sub-metre noise; no user locations.
        int index=0;var random=new Random(1);
        for(int i=0;i<raw.size();i++) {
            var p=raw.get(i);if(p.kind()!=Kind.GPS)continue;
            double north=index<=400?index:index<=600?400-(index-400):200+(index-600);
            double east=(index<=400?0:index<=600?5:10)+random.nextGaussian()*.8;
            north+=random.nextGaussian()*.8;index++;
            var point=new GeoPoint(37+Math.toDegrees(north/GeoPoint.EARTH_RADIUS_M),
                127+Math.toDegrees(east/(GeoPoint.EARTH_RADIUS_M*Math.cos(Math.toRadians(37)))));
            raw.set(i,new Input(p.seq(),p.kind(),p.elapsedMs(),p.measuredAt(),point,3.0,null));
        }
        upload(source,original,raw);
        var p=free.prepare(owner,source);
        assertThat(p.playback().eligible()).isFalse();
        assertThat(p.playback().unavailableReasons()).containsExactly("REFERENCE_NOT_REPRODUCIBLE");
        assertThat(p.diagnostics().reason()).isEqualTo("DISTANCE_SHORT");
        assertThat(p.diagnostics().recognizedPercent()).isLessThan(95);
        var built=new com.wadadak.run.internal.ghost.GhostPlaybackBuilder()
            .buildReference(runs.result(owner,source),p.playback().course(),raw);
        assertThat(p.playback()).isEqualTo(built);
        var expectedHash=HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256")
            .digest(json.writeValueAsString(built).getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        assertThat(p.referenceHash()).isEqualTo(expectedHash);
        String before=json.writeValueAsString(runs.result(owner,source));
        mvc.perform(get("/api/v1/runs/records/"+source+"/free-ghost-playback")
            .with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.diagnostics.reason").value("DISTANCE_SHORT"))
            .andExpect(jsonPath("$.data.diagnostics.recognizedDistanceM").isNumber())
            .andExpect(jsonPath("$.data.diagnostics.referenceDistanceM").isNumber())
            .andExpect(jsonPath("$.data.diagnostics.recognizedPercent").isNumber());
        assertThat(json.writeValueAsString(runs.result(owner,source))).isEqualTo(before);
    }

    List<Input> v2Fixture(String name,Instant at)throws Exception {
        var fixture=json.readTree(java.nio.file.Files.readString(java.nio.file.Path.of("../run/fixtures/free_ghost_tracker_v2.json")));
        for(var c:fixture.get("cases"))if(name.equals(c.get("name").asText())) {
            var raw=Arrays.asList(json.treeToValue(c.get("inputs"),Input[].class));
            return raw.stream().map(p->new Input(p.seq(),p.kind(),p.elapsedMs(),at.plusMillis(p.elapsedMs()),
                p.location(),p.accuracyM(),p.reason())).toList();
        }
        throw new AssertionError(name);
    }

    @Test void v2SourceAndIdenticalRunnerUseTheSameCompletionAndDrawWithoutCourseSideEffects(AssertablePublishedEvents events)throws Exception {
        var raw=v2Fixture("dense_nearby_legs",original);upload(source,original,raw);
        String before=json.writeValueAsString(runs.result(owner,source));
        assertThat(free.prepare(owner,source).playback().eligible()).isFalse();
        var p=free.prepare(owner,source,"GHOST_PLAYBACK_FREE_V2");
        assertThat(p.playback().eligible()).as(p.playback().unavailableReasons().toString()).isTrue();
        assertThat(p.playback().version()).isEqualTo("GHOST_PLAYBACK_FREE_V2");
        assertThat(p.playback().durationMs()).isLessThan(p.originalElapsedMs());
        mvc.perform(get("/api/v1/runs/records/"+source+"/free-ghost-playback")
            .with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.playback.version").value("GHOST_PLAYBACK_FREE_V1"));
        mvc.perform(get("/api/v1/runs/records/"+source+"/free-ghost-playback").param("playbackVersion","GHOST_PLAYBACK_FREE_V2")
            .with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.playback.eligible").value(true));
        var request=new GhostStart(null,1L,source,now,"GHOST_PLAYBACK_FREE_V2",p.referenceHash());
        mvc.perform(post("/api/v1/runs/sessions/"+id+"/ghost/start")
            .with(jwt().jwt(j->j.subject(owner.toString()))).contentType(MediaType.APPLICATION_JSON)
            .content(json.writeValueAsString(request))).andExpect(status().isOk())
            .andExpect(jsonPath("$.data.playback.version").value("GHOST_PLAYBACK_FREE_V2"));
        var approval=starts.start(owner,id,request);
        upload(id,now,v2Fixture("dense_nearby_legs",now));
        var result=runs.result(owner,id);
        assertThat(result.course()).isNull();
        assertThat(result.ghost().completed()).isTrue();
        assertThat(result.ghost().outcome()).isEqualTo(GhostVerdict.DRAW);
        assertThat(result.ghost().courseElapsedSeconds()).isEqualTo(p.playback().courseElapsedSeconds());
        assertThat(result.ghost().sourceDurationMs()).isEqualTo(p.playback().durationMs());
        assertThat(json.writeValueAsString(runs.result(owner,source))).isEqualTo(before);
        assertThat(db.queryForObject("SELECT count(*) FROM run.course_attempts",Long.class)).isZero();
        assertThat(events.ofType(CourseRunStartedEvent.class)).isEmpty();
        assertThat(events.ofType(RunSessionEndedEvent.class)).allMatch(e->e.courseId()==null && !e.completed());
        runs.delete(owner,source);
        assertThat(starts.start(owner,id,request)).isEqualTo(approval);
        assertThat(results.get(owner,id)).isEqualTo(result.ghost());
        verifyNoInteractions(courseApi);
    }

    @Test void alreadyApprovedV1DuelKeepsItsMatcherAndCannotBeUpgradedByRetry() {
        upload(source,original,raw(original,220,1200,2000,"INTERRUPTED",Set.of(),0));
        var p=free.prepare(owner,source);var request=request(p);var approval=starts.start(owner,id,request);
        var modern=free.prepare(owner,source,"GHOST_PLAYBACK_FREE_V2");
        assertThatThrownBy(()->starts.start(owner,id,new GhostStart(null,1L,source,now,"GHOST_PLAYBACK_FREE_V2",modern.referenceHash())))
            .isInstanceOf(AppException.class);
        assertThat(starts.start(owner,id,request)).isEqualTo(approval);
        upload(id,now,raw(now,220,1200,2000,"INTERRUPTED",Set.of(),0));
        assertThat(results.get(owner,id).outcome()).isEqualTo(GhostVerdict.DRAW);
        assertThat(results.get(owner,id).courseElapsedSeconds()).isEqualTo(p.playback().courseElapsedSeconds());
        assertThat(free.receipt(owner,id).orElseThrow().playback().version()).isEqualTo("GHOST_PLAYBACK_FREE_V1");
    }

    @Test void unknownFreeMatcherVersionIsRejectedInsteadOfSilentlyDowngraded()throws Exception {
        upload(source,original,raw(original,220,1200,2000,"INTERRUPTED",Set.of(),0));
        mvc.perform(get("/api/v1/runs/records/"+source+"/free-ghost-playback").param("playbackVersion","FUTURE")
            .with(jwt().jwt(j->j.subject(owner.toString())))).andExpect(status().isBadRequest());
    }

    @Test void gapsKeepDisconnectedGeometryAndRespectThirtySecondBoundary() {
        Set<Integer> missing=new HashSet<>();for(int i=100;i<114;i++) missing.add(i);
        upload(source,original,raw(original,600,3400,2000,"INTERRUPTED",missing,0));
        var p=free.prepare(owner,source);
        assertThat(p.playback().eligible()).as(p.playback().unavailableReasons().toString()).isTrue();
        assertThat(p.playback().quality().maxGapMs()).isEqualTo(30000);
        assertThat(p.playback().course().breaks()).isNotEmpty();
        assertThat(p.playback().course().totalDistanceMeters()).isLessThan(3400);
        UUID other=UUID.randomUUID();
        upload(other,original,raw(original,600,3400,2000,"INTERRUPTED",missing,1));
        assertThat(free.prepare(owner,other).playback().unavailableReasons()).contains("CONTINUOUS_GAP_EXCEEDED");
    }

    @Test void changedReferenceOrRetryBodyCannotStartAndOngoingSessionCannotBeConverted() {
        upload(source,original,raw(original,220,1200,2000,"USER",Set.of(),0));
        var p=free.prepare(owner,source);
        assertThatThrownBy(()->starts.start(owner,id,new GhostStart(null,1L,source,now,"GHOST_PLAYBACK_FREE_V1","bad"))).isInstanceOf(AppException.class);
        assertThat(db.queryForObject("SELECT count(*) FROM run.free_ghost_starts",Long.class)).isZero();
        starts.start(owner,id,request(p));
        assertThatThrownBy(()->starts.start(owner,id,new GhostStart(null,1L,source,now.plusSeconds(1),"GHOST_PLAYBACK_FREE_V1",p.referenceHash()))).isInstanceOf(AppException.class);
        UUID existing=UUID.randomUUID(); runs.prepare(owner,existing,new Prepare(now,"FREE"));
        assertThatThrownBy(()->starts.start(owner,existing,request(p))).isInstanceOf(AppException.class);
    }

    @Test void zeroDistanceDuelKeepsItsVerdictWithoutRegisteringAnOrdinaryRun() {
        upload(source,original,raw(original,220,1200,2000,"INTERRUPTED",Set.of(),0));
        var p=free.prepare(owner,source);starts.start(owner,id,request(p));
        List<Input> stopped=List.of(new Input(0,Kind.START,0,now,null,null,"PACE_V1"),
            new Input(1,Kind.PAUSE,0,now,null,null,null),
            new Input(2,Kind.END,600000,now.plusSeconds(600),null,null,"USER"));
        upload(id,now,stopped);
        assertThat(runs.status(owner,id).failure()).isEqualTo("ZERO_DISTANCE");
        assertThat(results.get(owner,id).outcome()).isEqualTo(GhostVerdict.LOSE);
        assertThat(db.queryForObject("SELECT count(*) FROM run.records WHERE id=?",Long.class,id)).isZero();
        assertThat(db.queryForObject("SELECT count(*) FROM run.free_ghost_results WHERE session_id=?",Long.class,id)).isEqualTo(1);
    }

    @Test void legacyFreeRecordCanBeSelectedAndApprovedThroughAuthenticatedHttp() throws Exception {
        var raw=new ArrayList<>(raw(original,220,1200,2000,"INTERRUPTED",Set.of(),0));
        raw.set(0,new Input(0,Kind.START,0,original,null,null,null));
        upload(source,original,raw);
        var p=free.prepare(owner,source);
        assertThat(p.playback().eligible()).as(p.playback().unavailableReasons().toString()).isTrue();
        mvc.perform(get("/api/v1/runs/ghost-candidates/own/free").with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.content[0].id").value(source.toString()));
        String path="/api/v1/runs/records/"+source+"/free-ghost-playback";
        mvc.perform(get(path).with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.playback.eligible").value(true));
        mvc.perform(get(path).with(jwt().jwt(j->j.subject(UUID.randomUUID().toString()))))
            .andExpect(status().isNotFound());
        String start="/api/v1/runs/sessions/"+id+"/ghost/start";
        mvc.perform(post(start).with(jwt().jwt(j->j.subject(owner.toString())))
            .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(request(p))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.version").value("GHOST_START_FREE_V1"));
        mvc.perform(get(start).with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.sourceRecordId").value(source.toString()));
        verifyNoInteractions(courseApi);
    }

    @Test void aPrivateDuelRecordIsStillAFreeSourceAndKeepsItsOriginalVerdict() {
        upload(source,original,raw(original,220,1200,2000,"INTERRUPTED",Set.of(),0));
        var prepared=free.prepare(owner,source);starts.start(owner,id,request(prepared));
        upload(id,now,raw(now,220,1200,1000,"INTERRUPTED",Set.of(),0));
        var priorVerdict=results.get(owner,id);
        var nextSource=free.prepare(owner,id);
        assertThat(nextSource.playback().eligible()).as(nextSource.playback().unavailableReasons().toString()).isTrue();
        assertThat(free.candidates(owner,OwnGhostPeriod.ALL,20,null).content()).extracting(FreeGhostCandidate::id).contains(id);
        UUID next=UUID.randomUUID();
        starts.start(owner,next,new GhostStart(null,1L,id,now.plusSeconds(1000),"GHOST_PLAYBACK_FREE_V1",nextSource.referenceHash()));
        assertThat(results.get(owner,id)).isEqualTo(priorVerdict);
        assertThat(db.queryForObject("SELECT count(*) FROM run.course_attempts",Long.class)).isZero();
        verifyNoInteractions(courseApi);
    }

    @Test void cumulativeFivePercentBoundaryIsIndependentOfTheThirtySecondLimit() {
        Set<Integer> missing=new HashSet<>();
        for(int base:List.of(100,200,300))for(int i=base;i<base+9;i++)missing.add(i);
        var sourceRaw=raw(original,600,3400,2000,"INTERRUPTED",missing,0);
        List<Input> delayed=new ArrayList<>();
        for(var p:sourceRaw){
            if(p.kind()==Kind.GPS && p.elapsedMs()==0){
                delayed.add(new Input(delayed.size(),p.kind(),0,original,p.location(),3.0,null));
                for(int i=1;i<=2;i++)delayed.add(new Input(delayed.size(),Kind.GPS,i*2000,original.plusMillis(i*2000),p.location(),3.0,null));
            }else{
                long ms=p.elapsedMs()+(p.kind()==Kind.START?0:4000);
                delayed.add(new Input(delayed.size(),p.kind(),ms,original.plusMillis(ms),p.location(),p.accuracyM(),p.reason()));
            }
        }
        upload(source,original,delayed);
        var replay=free.prepare(owner,source).playback();
        assertThat(replay.quality().maxGapMs()).isEqualTo(20000);
        assertThat(replay.quality().gapMs()).isEqualTo(60000);
        assertThat(replay.quality().activeDurationMs()).isEqualTo(1200000);
        assertThat(replay.eligible()).as(replay.unavailableReasons().toString()).isTrue();
        UUID other=UUID.randomUUID();
        List<Input> faster=new ArrayList<>();
        for(var p:delayed){long ms=p.elapsedMs()>4000?p.elapsedMs()-1:p.elapsedMs();
            faster.add(new Input(p.seq(),p.kind(),ms,original.plusMillis(ms),p.location(),p.accuracyM(),p.reason()));}
        upload(other,original,faster);
        assertThat(free.prepare(owner,other).playback().unavailableReasons()).contains("TOTAL_GAP_EXCEEDED");
    }
}
