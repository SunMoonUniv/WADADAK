package com.wadadak.run.internal.recording;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.*;
import com.wadadak.event.member.MemberVisibilityChangedEvent;
import com.wadadak.event.run.CourseRunStartedEvent;
import com.wadadak.ranking.*;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import java.nio.file.*;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.*;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@ApplicationModuleTest @AutoConfigureMockMvc @ActiveProfiles("test") @Import(TestcontainersConfiguration.class)
class PublicGhostTest {
    @Autowired CourseRunService courses;
    @Autowired RunService runs;
    @Autowired PublicGhostService publicGhosts;
    @Autowired PublicGhostAccess access;
    @Autowired GhostStartService starts;
    @Autowired GhostStartStore receipts;
    @Autowired GhostResultService results;
    @Autowired JdbcTemplate db;
    @Autowired MockMvc mvc;
    @Autowired JsonMapper json;
    @MockitoBean CourseApi courseApi;
    @MockitoBean RankingApi ranking;
    @MockitoBean RunProcessingWorker processing;
    @MockitoBean CourseRunReleaseWorker release;
    @MockitoBean GpsGapWorker gpsGaps;
    UUID donor,owner,source,id,course;
    CourseRouteSnapshot current;
    List<Input> raw;
    final Instant at=Instant.parse("2026-10-26T00:00:00Z"),start=Instant.parse("2026-10-27T00:00:00Z");
    @BeforeEach void setup()throws Exception {
        for(String table:List.of("course_attempts","course_runner_counts","member_visibility_copies","withdrawn_members","deleted_records","records","inputs","sessions"))db.update("DELETE FROM run."+table);
        donor=UUID.randomUUID();owner=UUID.randomUUID();source=UUID.randomUUID();id=UUID.randomUUID();course=UUID.randomUUID();
        var fixture=json.readTree(Files.readString(Path.of("../run/fixtures/ghost_playback_v1.json")));
        List<GeoPoint> route=new ArrayList<>();for(var p:fixture.get("route"))route.add(json.treeToValue(p,GeoPoint.class));
        current=new CourseRouteSnapshot(course,"공개 테스트 코스",route,1000,3);
        when(courseApi.getRouteForRun(course)).thenReturn(current);
        raw=new ArrayList<>();for(var p:fixture.get("cases").get(1).get("inputs"))raw.add(json.treeToValue(p,Input.class));
        upload(donor,source,at,raw);courses.prepare(owner,id,course);
        when(ranking.findPublicGhostCandidate(course,RankingPeriod.ALL,owner,source)).thenAnswer(call->{
            assertThat(TransactionSynchronizationManager.isActualTransactionActive()).isFalse();
            return Optional.of(new GhostCandidate(source,donor,14,230));
        });
    }
    void upload(UUID member,UUID record,Instant date,List<Input> inputs){
        courses.prepare(member,record,course);courses.start(member,record,date);
        runs.prepare(member,record,new Prepare(date,"COURSE"));runs.upload(member,record,new Upload(inputs.size()-1,inputs));runs.process(record);
    }
    GhostStart request(){return new GhostStart(course,3L,source,start,"GHOST_PLAYBACK_V1",null,RankingPeriod.ALL);}
    void unavailable(Runnable action){assertThatThrownBy(action::run).isInstanceOfSatisfying(AppException.class,e->assertThat(e.getErrorCode()).isEqualTo(RunErrorCode.GHOST_UNAVAILABLE));}
    void visibility(boolean value,long version){access.visibility(new MemberVisibilityChangedEvent(UUID.randomUUID(),start,donor,value,version));}
    @Test void authenticatedPublicReplayExposesDerivedPositionsButKeepsOwnRecordApiPrivate()throws Exception{
        mvc.perform(get("/api/v1/runs/records/"+source+"/public-ghost-playback").param("courseId",course.toString()).with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.candidate.rank").value(14))
            .andExpect(jsonPath("$.data.playback.eligible").value(true)).andExpect(jsonPath("$.data.playback.durationMs").value(230000))
            .andExpect(jsonPath("$.data.playback.inputs").doesNotExist()).andExpect(jsonPath("$.data.playback.metrics").doesNotExist());
        mvc.perform(get("/api/v1/runs/records/"+source+"/ghost-playback").with(jwt().jwt(j->j.subject(owner.toString())))).andExpect(status().isNotFound());
        mvc.perform(get("/api/v1/runs/records/"+source).with(jwt().jwt(j->j.subject(owner.toString())))).andExpect(status().isNotFound());
    }
    @Test void approvalFreezesPublicPeriodAndSurvivesSourceDeletionAndPrivacyChange(AssertablePublishedEvents events)throws Exception{
        mvc.perform(post("/api/v1/runs/sessions/"+id+"/ghost/start").with(jwt().jwt(j->j.subject(owner.toString())))
            .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(request())))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.publicPeriod").value("ALL"));
        var receipt=receipts.get(owner,id);
        visibility(false,2);runs.delete(donor,source);
        when(ranking.findPublicGhostCandidate(course,RankingPeriod.ALL,owner,source)).thenThrow(new IllegalStateException("must not revalidate a saved approval"));
        assertThat(starts.start(owner,id,request())).isEqualTo(receipt);
        assertThat(events.ofType(CourseRunStartedEvent.class).matching(e->e.runSessionId().equals(id))).hasSize(1);
        var shifted=raw.stream().map(p->new Input(p.seq(),p.kind(),p.elapsedMs(),start.plusMillis(p.elapsedMs()),p.location(),p.accuracyM(),p.reason())).toList();
        runs.prepare(owner,id,new Prepare(start,"COURSE"));runs.upload(owner,id,new Upload(shifted.size()-1,shifted));runs.process(id);
        assertThat(runs.result(owner,id).ghost().outcome()).isEqualTo(GhostVerdict.DRAW);
        var detail=results.comparison(owner,id);
        assertThat(detail.publicPeriod()).isEqualTo("ALL");assertThat(detail.sourceKind()).isEqualTo("PUBLIC_COURSE");
        assertThat(detail.sourceState()).isEqualTo("DELETED");
        assertThat(detail.ghost().elapsedSeconds()).isEqualTo(230);
        assertThat(detail.ghost().activeMs()).isNull();assertThat(detail.ghost().averageCadence()).isNull();
        mvc.perform(get("/api/v1/runs/sessions/"+id+"/ghost/result/comparison").with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.publicPeriod").value("ALL"))
            .andExpect(jsonPath("$.data.ghost.averageCadence").isEmpty())
            .andExpect(jsonPath("$.data.sourceOwner").doesNotExist());

    }
    @Test void privacyProjectionFailsClosedEvenWhenRankingIsStaleAndOldEventsCannotReopenIt(){
        visibility(false,3);visibility(true,2);
        unavailable(()->publicGhosts.prepare(owner,course,RankingPeriod.ALL,source));
        unavailable(()->starts.start(owner,id,request()));
        assertThat(db.queryForObject("SELECT count(*) FROM run.ghost_starts",Long.class)).isZero();
        visibility(true,4);assertThat(publicGhosts.prepare(owner,course,RankingPeriod.ALL,source).playback().eligible()).isTrue();
    }
    @Test void missingCandidateWrongPeriodDeletionAndSelfSourceCannotBeApproved(){
        unavailable(()->publicGhosts.prepare(owner,course,RankingPeriod.WEEK,source));
        when(ranking.findPublicGhostCandidate(course,RankingPeriod.ALL,owner,source)).thenReturn(Optional.empty());
        unavailable(()->starts.start(owner,id,request()));
        when(ranking.findPublicGhostCandidate(course,RankingPeriod.ALL,owner,source)).thenReturn(Optional.of(new GhostCandidate(source,owner,1,230)));
        unavailable(()->publicGhosts.prepare(owner,course,RankingPeriod.ALL,source));
        when(ranking.findPublicGhostCandidate(course,RankingPeriod.ALL,owner,source)).thenReturn(Optional.of(new GhostCandidate(source,donor,1,230)));
        runs.delete(donor,source);unavailable(()->starts.start(owner,id,request()));
    }
    @Test void unsupportedCourseVersionAndWithdrawalBlockNewSelectionButCachedApprovalRemains(){
        var changed=new ArrayList<>(current.route());changed.set(1,new GeoPoint(changed.get(1).lat()+0.001,changed.get(1).lng()));
        when(courseApi.getRouteForRun(course)).thenReturn(new CourseRouteSnapshot(course,current.name(),changed,1000,4));
        unavailable(()->publicGhosts.prepare(owner,course,RankingPeriod.ALL,source));
        when(courseApi.getRouteForRun(course)).thenReturn(current);
        var receipt=starts.start(owner,id,request());runs.withdraw(donor,start);
        unavailable(()->publicGhosts.prepare(owner,course,RankingPeriod.ALL,source));
        assertThat(starts.start(owner,id,request())).isEqualTo(receipt);
        assertThatThrownBy(()->starts.start(owner,id,new GhostStart(course,3L,source,start,"GHOST_PLAYBACK_V1"))).isInstanceOf(AppException.class);
        assertThatThrownBy(()->starts.start(owner,id,new GhostStart(course,3L,source,start,"GHOST_PLAYBACK_V1",null,RankingPeriod.WEEK))).isInstanceOf(AppException.class);
    }
    @Test void oppositePublicDuelsAcquireMemberLocksInStableOrder()throws Exception{
        UUID second=UUID.randomUUID(),secondDuel=UUID.randomUUID();upload(owner,second,at,raw);courses.prepare(donor,secondDuel,course);
        var ready=new CyclicBarrier(2);
        when(ranking.findPublicGhostCandidate(course,RankingPeriod.ALL,owner,source)).thenAnswer(call->{ready.await(10,TimeUnit.SECONDS);return Optional.of(new GhostCandidate(source,donor,1,230));});
        when(ranking.findPublicGhostCandidate(course,RankingPeriod.ALL,donor,second)).thenAnswer(call->{ready.await(10,TimeUnit.SECONDS);return Optional.of(new GhostCandidate(second,owner,1,230));});
        try(var pool=Executors.newFixedThreadPool(2)){
            var a=pool.submit(()->starts.start(owner,id,request()));
            var b=pool.submit(()->starts.start(donor,secondDuel,new GhostStart(course,3L,second,start,"GHOST_PLAYBACK_V1",null,RankingPeriod.ALL)));
            assertThat(a.get(20,TimeUnit.SECONDS).sourceRecordId()).isEqualTo(source);
            assertThat(b.get(20,TimeUnit.SECONDS).sourceRecordId()).isEqualTo(second);
        }
    }

    @Test void retentionMetadataVersionDoesNotInvalidateAnUnchangedHistoricalRoute(){
        String originalJson=db.queryForObject("SELECT result_json FROM run.records WHERE id=?",String.class,source);
        var metadata=new CourseRouteSnapshot(course,current.name(),current.route(),1000,4);
        when(courseApi.getRouteForRun(course)).thenReturn(metadata);
        var p=publicGhosts.prepare(owner,course,RankingPeriod.ALL,source);
        assertThat(p.sourceCourseVersion()).isEqualTo(3);
        assertThat(p.playback().course().version()).isEqualTo(4);
        UUID duel=UUID.randomUUID();courses.prepare(owner,duel,course);
        var receipt=starts.start(owner,duel,new GhostStart(course,4L,source,start,"GHOST_PLAYBACK_V1",null,RankingPeriod.ALL));
        assertThat(receipt.playback().course().version()).isEqualTo(4);
        assertThat(db.queryForObject("SELECT source_course_version FROM run.ghost_starts WHERE session_id=?",Long.class,duel)).isEqualTo(3);
        assertThat(db.queryForObject("SELECT result_json FROM run.records WHERE id=?",String.class,source)).isEqualTo(originalJson);
    }
}
