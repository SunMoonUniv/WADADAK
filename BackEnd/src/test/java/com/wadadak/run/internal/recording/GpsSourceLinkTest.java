package com.wadadak.run.internal.recording;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.CourseApi;
import com.wadadak.event.course.*;
import com.wadadak.event.run.*;
import com.wadadak.member.MemberApi;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingPeriod;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.judging.CourseJudge;
import com.wadadak.course.internal.registration.GpsSourcePublicationService;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.awaitility.Awaitility.await;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Real, isolated PostGIS and real cross-module listeners. No development/production records are used. */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class GpsSourceLinkTest {
    @Autowired RunService runs;
    @Autowired GpsSourceLinkService links;
    @Autowired GhostPlaybackService playback;
    @Autowired OwnGhostCandidates candidates;
    @Autowired GhostStartStore starts;
    @Autowired CourseRunService courseRuns;
    @Autowired RankingApi ranking;
    @Autowired CourseApi courseApi;
    @Autowired GpsSourcePublicationService publications;
    @Autowired JdbcTemplate db;
    @Autowired JsonMapper json;
    @Autowired MockMvc mvc;
    @Autowired ApplicationEventPublisher events;
    @Autowired TransactionTemplate tx;
    @MockitoBean MemberApi members;
    @MockitoBean RunProcessingWorker processing;
    @MockitoBean GpsGapWorker gapWorker;
    @MockitoBean CourseRunReleaseWorker releaseWorker;
    @MockitoBean GpsSourceLinkWorker linkWorker;
    final Instant epoch=Instant.parse("2026-10-15T00:00:00Z");
    static final java.util.concurrent.atomic.AtomicInteger paths=new java.util.concurrent.atomic.AtomicInteger();

    record Source(UUID owner,UUID id,Result result,List<Input> raw) {}

    Source source(boolean gap,boolean segmentEnd,String reason) {
        UUID owner=UUID.randomUUID(),id=UUID.randomUUID();
        double longitude=126.9+paths.getAndIncrement()*0.005;
        List<Input> raw=new ArrayList<>();
        raw.add(new Input(0,Kind.START,0,epoch,null,null,null));
        for(int i=0;i<=400;i++) {
            long ms=i*1000L+(gap&&i>200?120000:0);
            double meters=i*3+(gap&&i>200?300:0);
            raw.add(new Input(raw.size(),Kind.GPS,ms,epoch.plusMillis(ms),new GeoPoint(point(meters).lat(),longitude),3.0,null));
            if(segmentEnd&&i==200)
                raw.add(new Input(raw.size(),Kind.SEGMENT_END,ms,epoch.plusMillis(ms),null,null,"USER_SEGMENT_END"));
        }
        long duration=raw.getLast().elapsedMs();
        if("USER_END".equals(reason)) raw.add(new Input(raw.size(),Kind.PAUSE,duration,epoch.plusMillis(duration),null,null,null));
        raw.add(new Input(raw.size(),Kind.END,duration,epoch.plusMillis(duration),null,null,"USER_END".equals(reason)?"USER":reason));
        runs.prepare(owner,id,new Prepare(epoch,"FREE"));
        runs.upload(owner,id,new Upload(raw.size()-1,raw));
        runs.process(id);
        assertThat(runs.status(owner,id).processing()).as(runs.status(owner,id).failure()).isEqualTo("DONE");
        await().atMost(Duration.ofSeconds(15)).untilAsserted(()->assertThat(count(
                "SELECT count(*) FROM ranking.distance_run_records WHERE run_record_id=?",id)).isOne());
        return new Source(owner,id,runs.result(owner,id),List.copyOf(raw));
    }
    static GeoPoint point(double m) {return new GeoPoint(37.556+m/111195.0802335,126.9);}

    GpsCourseRegisteredEvent evidence(Source s) {
        var segments=runs.courseSource(s.owner(),s.id()).segments().stream()
                .map(part->part.stream().map(p->new GeoPoint(p.lat(),p.lng())).toList()).toList();
        var route=List.of(segments.getFirst().getFirst(),segments.getLast().getLast());
        int distance=(int)Math.round(route.getFirst().distanceMeters(route.getLast()));
        UUID course=UUID.randomUUID();
        db.update("""
            INSERT INTO course.courses(id,creator_id,course_type,name,name_key,difficulty,tags,route,distance_meters,
                start_point,emd_code,sigungu_code,sido_code,status,expires_at,version,created_at,updated_at)
            VALUES (?,?,'GPS',?,?,'EASY','{}'::varchar[],ST_GeomFromText(?,4326),?,
                ST_GeogFromText('SRID=4326;POINT(126.9 37.556)'),'1171010100','1171000000','1100000000',
                'ACTIVE',?,0,now(),now())
            """,course,s.owner(),"자동 연결 "+course,"자동연결"+course,
                "LINESTRING("+route.getFirst().lng()+" "+route.getFirst().lat()+","+route.getLast().lng()+" "+route.getLast().lat()+")",
                distance,Timestamp.from(Instant.now().plusSeconds(30*86400)));
        return new GpsCourseRegisteredEvent(UUID.randomUUID(),Instant.now(),course,s.owner(),s.id(),
                "자동 연결 "+course,route,distance,0,CourseStatus.ACTIVE,segments);
    }

    @Test void linksExactlyOnceWithoutChangingOriginalOrPersonalDistanceAndUsesFullSessionForGhost() {
        var s=source(false,false,"USER_END");var e=evidence(s);
        String original=saved(s.id()),raw=raw(s.id());
        var expires=db.queryForObject("SELECT expires_at FROM course.courses WHERE id=?",Timestamp.class,e.courseId());
        links.receive(e);links.receive(e);
        linkedCopies(s,e);
        assertThat(saved(s.id())).isEqualTo(original);
        assertThat(raw(s.id())).isEqualTo(raw);
        assertThat(count("SELECT count(*) FROM run.sessions WHERE member_id=?",s.owner())).isOne();
        assertThat(count("SELECT count(*) FROM run.course_attempts WHERE member_id=?",s.owner())).isZero();
        assertThat(count("SELECT count(*) FROM ranking.distance_run_records WHERE member_id=?",s.owner())).isOne();
        assertThat(db.queryForObject("SELECT expires_at FROM course.courses WHERE id=?",Timestamp.class,e.courseId())).isEqualTo(expires);
        assertThat(db.queryForObject("SELECT challenge_count FROM course.course_stats WHERE course_id=?",Integer.class,e.courseId())).isZero();
        assertThat(count("SELECT count(*) FROM course.course_active_runners WHERE course_id=?",e.courseId())).isZero();
        var replay=playback.own(s.owner(),s.id());
        assertThat(replay.eligible()).as(replay.unavailableReasons().toString()).isTrue();
        assertThat(replay.version()).isEqualTo("GHOST_PLAYBACK_GPS_SOURCE_V1");
        assertThat(replay.durationMs()).isEqualTo(s.result().metrics().elapsedMs());
        assertThat(new CourseJudge().analyze(e.route(),List.of(),s.raw()).courseElapsedMs()).isLessThan(replay.durationMs());
        var list=candidates.list(s.owner(),e.courseId(),0,OwnGhostSort.BEST,OwnGhostPeriod.ALL,new Cursorable(null,20));
        assertThat(list.content()).extracting(OwnGhostCandidate::id).containsExactly(s.id());
    }

    @Test void registeredSourceCanStartAndApprovalSurvivesDeletionWithVersionAndTimePinned() throws Exception {
        var s=source(false,false,"USER_END");var e=evidence(s);links.receive(e);linkedCopies(s,e);
        UUID duel=UUID.randomUUID();courseRuns.prepare(s.owner(),duel,e.courseId());
        var request=new GhostStart(e.courseId(),0L,s.id(),Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MICROS),
                "GHOST_PLAYBACK_GPS_SOURCE_V1");
        mvc.perform(post("/api/v1/runs/sessions/"+duel+"/ghost/start").with(jwt().jwt(j->j.subject(s.owner().toString())))
            .contentType("application/json").content(json.writeValueAsString(request)))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.playback.version").value("GHOST_PLAYBACK_GPS_SOURCE_V1"));
        var saved=starts.get(s.owner(),duel);
        runs.delete(s.owner(),s.id());
        mvc.perform(post("/api/v1/runs/sessions/"+duel+"/ghost/start").with(jwt().jwt(j->j.subject(s.owner().toString())))
            .contentType("application/json").content(json.writeValueAsString(request)))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.playback.durationMs").value(400000));
        assertThat(starts.get(s.owner(),duel)).isEqualTo(saved);
    }

    @Test void joinedGapDoesNotBecomeMeasuredDistanceAndDoesNotGateAutomaticCompletion() {
        var s=source(true,false,"INTERRUPTED");var e=evidence(s);
        links.receive(e);linkedCopies(s,e);
        var p=links.linked(s.owner(),s.id()).orElseThrow().performance();
        assertThat(p.progress()).isBetween(70.0,90.0);
        assertThat(p.recognizedDistanceMeters()).isLessThan((double)e.distanceMeters());
        assertThat(p.reviewEligible()).isTrue();
        assertThat(links.status(s.owner(),s.id()).status()).isEqualTo("LINKED");
        assertThat(playback.own(s.owner(),s.id()).eligible()).isFalse();
        assertThat(runs.result(s.owner(),s.id()).endReason()).isEqualTo("INTERRUPTED");
        assertThat(runs.result(s.owner(),s.id()).metrics().distanceM()).isEqualTo(s.result().metrics().distanceM());
    }

    @Test void freeGhostSegmentEndDoesNotTruncateFullSessionSourceOrRecognizedDistance() {
        var s=source(false,true,"USER_END");var e=evidence(s);
        links.receive(e);linkedCopies(s,e);
        var p=links.linked(s.owner(),s.id()).orElseThrow().performance();
        assertThat(p.courseElapsedSeconds()).isEqualTo(400);
        assertThat(p.recognizedDistanceMeters()).isGreaterThan(1100);
        var replay=playback.own(s.owner(),s.id());
        assertThat(replay.durationMs()).isEqualTo(400000);
        assertThat(replay.eligible()).isTrue();
    }

    @Test void originalRegistrationTimeControlsMonthAndWeekAndIsNotLinkTime() {
        var s=source(false,false,"USER_END");
        Instant old=Instant.now().minus(Duration.ofDays(40)).truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        var result=s.result();
        var historical=new Result(result.id(),result.startedAt(),result.endedAt(),old,result.endReason(),result.metrics(),
                result.routeSegments(),result.laps(),result.policyVersion(),result.calculationVersion(),result.stats(),
                result.course(),result.gpsGap(),result.ghost());
        db.update("UPDATE run.records SET result_json=?,registered_at=? WHERE id=?",
                json.writeValueAsString(historical),Timestamp.from(old),s.id());
        var e=evidence(s);links.receive(e);linkedCopies(s,e);
        when(members.getProfiles(any())).thenReturn(List.of());
        UUID requester=UUID.randomUUID();
        assertThat(ranking.getPublicGhostCandidates(e.courseId(),RankingPeriod.ALL,requester,10)).hasSize(1);
        assertThat(ranking.getPublicGhostCandidates(e.courseId(),RankingPeriod.MONTH,requester,10)).isEmpty();
        assertThat(ranking.getPublicGhostCandidates(e.courseId(),RankingPeriod.WEEK,requester,10)).isEmpty();
        assertThat(db.queryForObject("SELECT registered_at FROM ranking.course_ranking_entries WHERE run_record_id=?",
                Timestamp.class,s.id()).toInstant()).isEqualTo(old.truncatedTo(java.time.temporal.ChronoUnit.MICROS));
    }

    @Test void rejectsForeignOrChangedSourceAndHiddenCourseWithoutRewritingRecord() {
        var s=source(false,false,"USER_END");var e=evidence(s);
        String original=saved(s.id());
        var bad=new GpsCourseRegisteredEvent(e.eventId(),e.occurredAt(),e.courseId(),UUID.randomUUID(),s.id(),
                e.courseName(),e.route(),e.distanceMeters(),0,CourseStatus.ACTIVE,e.sourceSegments());
        links.receive(bad);
        assertThat(db.queryForObject("SELECT failure FROM run.gps_source_links WHERE source_record_id=?",String.class,s.id()))
                .isEqualTo("SOURCE_OWNER_MISMATCH");
        assertThat(saved(s.id())).isEqualTo(original);
        var another=source(false,false,"USER_END");var hidden=evidence(another);
        links.courseStatus(new CourseStatusChangedEvent(UUID.randomUUID(),Instant.now(),hidden.courseId(),
                CourseStatus.HIDDEN,CourseStatusReason.EXPIRED,2));
        links.receive(hidden);
        assertThat(links.status(another.owner(),another.id()).failure()).isEqualTo("COURSE_UNAVAILABLE");
    }

    @Test void rejectsChangedRegistrationSegmentsWithoutAffectingOriginal() {
        var s=source(false,false,"USER_END");var e=evidence(s);
        var changed=new ArrayList<>(e.sourceSegments().getFirst());changed.set(2,point(999));
        links.receive(new GpsCourseRegisteredEvent(e.eventId(),e.occurredAt(),e.courseId(),e.creatorId(),s.id(),
                e.courseName(),e.route(),e.distanceMeters(),0,CourseStatus.ACTIVE,List.of(changed)));
        assertThat(links.status(s.owner(),s.id()).failure()).isEqualTo("SOURCE_ROUTE_MISMATCH");
        assertThat(count("SELECT count(*) FROM ranking.course_ranking_entries WHERE run_record_id=?",s.id())).isZero();
    }

    @Test void deletionRemovesOnlyCourseContributionAndCannotBeResurrectedByLateEvidence() {
        var s=source(false,false,"USER_END");var e=evidence(s);links.receive(e);linkedCopies(s,e);
        runs.delete(s.owner(),s.id());links.receive(e);
        await().atMost(Duration.ofSeconds(15)).untilAsserted(()-> {
            assertThat(db.queryForObject("SELECT completion_count FROM course.course_stats WHERE course_id=?",Integer.class,e.courseId())).isZero();
            assertThat(db.queryForObject("SELECT deleted FROM ranking.course_ranking_entries WHERE run_record_id=?",Boolean.class,s.id())).isTrue();
            assertThat(db.queryForObject("SELECT deleted FROM review.course_run_records WHERE run_record_id=?",Boolean.class,s.id())).isTrue();
            assertThat(db.queryForObject("SELECT deleted FROM ranking.distance_run_records WHERE run_record_id=?",Boolean.class,s.id())).isTrue();
        });
        assertThat(db.queryForObject("SELECT status FROM run.gps_source_links WHERE source_record_id=?",String.class,s.id())).isEqualTo("REMOVED");
        assertThat(db.queryForObject("SELECT snapshot_json FROM run.gps_source_links WHERE source_record_id=?",String.class,s.id())).isNull();
        assertThat(count("SELECT count(*) FROM course.courses WHERE id=?",e.courseId())).isOne();
        assertThat(db.queryForObject("SELECT challenge_count FROM course.course_stats WHERE course_id=?",Integer.class,e.courseId())).isZero();
    }

    @Test void deletionBeforeRegistrationEvidenceIsTerminalAndDoesNotRetainSourceGeometry() {
        var s=source(false,false,"USER_END");var e=evidence(s);runs.delete(s.owner(),s.id());links.receive(e);
        assertThat(db.queryForObject("SELECT failure FROM run.gps_source_links WHERE source_record_id=?",String.class,s.id())).isEqualTo("SOURCE_DELETED");
        assertThat(db.queryForObject("SELECT snapshot_json FROM run.gps_source_links WHERE source_record_id=?",String.class,s.id())).isNull();
    }

    @Test void withdrawalUnlinksWithoutDeletingRegisteredCourse() {
        var s=source(false,false,"USER_END");var e=evidence(s);links.receive(e);linkedCopies(s,e);
        runs.withdraw(s.owner(),Instant.now());
        await().atMost(Duration.ofSeconds(15)).untilAsserted(()->assertThat(
                db.queryForObject("SELECT completion_count FROM course.course_stats WHERE course_id=?",Integer.class,e.courseId())).isZero());
        assertThat(count("SELECT count(*) FROM run.sessions WHERE member_id=?",s.owner())).isZero();
        assertThat(count("SELECT count(*) FROM course.courses WHERE id=?",e.courseId())).isOne();
    }

    @Test void simultaneousDuplicateDeliveryAndDeletionDoNotLeaveAnyLivePerformance() {
        var s=source(false,false,"USER_END");var e=evidence(s);
        CompletableFuture.allOf(CompletableFuture.runAsync(()->links.receive(e)),
                CompletableFuture.runAsync(()->links.receive(e)),CompletableFuture.runAsync(()->runs.delete(s.owner(),s.id()))).join();
        drain();
        await().atMost(Duration.ofSeconds(15)).untilAsserted(()->assertThat(
                count("SELECT count(*) FROM ranking.course_ranking_entries WHERE run_record_id=? AND NOT deleted",s.id())).isZero());
        assertThat(db.queryForObject("SELECT status FROM run.gps_source_links WHERE source_record_id=?",String.class,s.id()))
                .isIn("REMOVED","REJECTED");
    }

    @Test void pendingUploadCanCompleteAndBeRetriedWithoutAnotherRegistration() {
        var template=source(false,false,"USER_END");var old=evidence(template);
        UUID id=UUID.randomUUID();
        runs.prepare(template.owner(),id,new Prepare(epoch,"FREE"));
        runs.upload(template.owner(),id,new Upload(template.raw().size()-1,template.raw()));
        var e=new GpsCourseRegisteredEvent(UUID.randomUUID(),Instant.now(),old.courseId(),template.owner(),id,
                old.courseName(),old.route(),old.distanceMeters(),0,CourseStatus.ACTIVE,old.sourceSegments());
        links.receive(e);
        assertThat(links.status(template.owner(),id).status()).isEqualTo("PENDING");
        assertThat(links.status(template.owner(),id).failure()).isEqualTo("SOURCE_PROCESSING");
        runs.process(id);links.process(id);links.process(id);
        linkedCopies(new Source(template.owner(),id,runs.result(template.owner(),id),template.raw()),e);
    }

    @Test void explicitLegacyPublicationIsIdempotentAndGivesOwnerOnlyStatus() throws Exception {
        var s=source(false,false,"USER_END");var e=evidence(s);
        var source=runs.courseSource(s.owner(),s.id());
        db.update("INSERT INTO course.gps_course_sources(course_id,run_record_id,member_id,source_segments_json,created_at,updated_at) VALUES (?,?,?,?,now(),now())",
                e.courseId(),s.id(),s.owner(),json.writeValueAsString(source.segments()));
        publications.publish(e.courseId());publications.publish(e.courseId());
        linkedCopies(s,e);
        assertThat(db.queryForObject("SELECT completion_snapshot_json FROM course.gps_course_sources WHERE course_id=?",String.class,e.courseId())).isNotNull();
        mvc.perform(get("/api/v1/runs/records/"+s.id()+"/gps-course-link").with(jwt().jwt(j->j.subject(s.owner().toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.status").value("LINKED"));
        mvc.perform(get("/api/v1/runs/records/"+s.id()+"/gps-course-link").with(jwt().jwt(j->j.subject(UUID.randomUUID().toString()))))
            .andExpect(status().isNotFound());
    }

    @Test void newGpsRegistrationPublishesEvidenceAndStartsLinkWithoutAnotherRun() throws Exception {
        var s=source(false,false,"USER_END");
        Map<String,Object> body=new LinkedHashMap<>();
        body.put("sourceRunRecordId",s.id());body.put("segments",runs.courseSource(s.owner(),s.id()).segments());
        body.put("name","새 등록 "+UUID.randomUUID());body.put("difficulty","EASY");body.put("tags",List.of());
        var response=mvc.perform(post("/api/v1/courses/gps").with(jwt().jwt(j->j.subject(s.owner().toString())))
            .header("Idempotency-Key",UUID.randomUUID()).contentType("application/json").content(json.writeValueAsString(body)))
            .andExpect(status().isOk()).andReturn();
        var course=UUID.fromString(json.readTree(response.getResponse().getContentAsString()).get("data").get("courseId").asText());
        await().atMost(Duration.ofSeconds(15)).untilAsserted(()->assertThat(links.status(s.owner(),s.id()).status()).isEqualTo("LINKED"));
        assertThat(count("SELECT count(*) FROM run.sessions WHERE member_id=?",s.owner())).isOne();
        await().atMost(Duration.ofSeconds(15)).untilAsserted(()->assertThat(count("SELECT count(*) FROM course.gps_source_completion_receipts WHERE course_id=?",course)).isOne());
    }

    @Test void removalFirstDeliveryNeverCreatesACompletionOrDistanceCopy() {
        var s=source(false,false,"USER_END");var e=evidence(s);
        var p=new GpsSourceLinkedEvent(UUID.randomUUID(),Instant.now(),s.id(),s.owner(),e.courseId(),400,e.distanceMeters(),
                1200.0,100.0,true,s.result().endedAt(),epoch,s.result().endedAt(),s.result().registeredAt(),"GPS_SOURCE_COMPLETION_V1");
        publish(new GpsSourceUnlinkedEvent(UUID.randomUUID(),Instant.now(),p,"SOURCE_DELETED"));drain();
        // Real redelivery retains the event ID but creates a distinct message instance.
        // Reusing one object concurrently collides with Modulith's in-flight publication keys.
        var redelivery=json.readValue(json.writeValueAsString(p),GpsSourceLinkedEvent.class);
        assertThat(redelivery).isEqualTo(p).isNotSameAs(p);
        publish(p);publish(redelivery);drain();
        assertThat(count("SELECT count(*) FROM course.course_completions WHERE run_record_id=? AND deleted_at IS NULL",s.id())).isZero();
        assertThat(count("SELECT count(*) FROM ranking.course_ranking_entries WHERE run_record_id=? AND NOT deleted",s.id())).isZero();
        assertThat(count("SELECT count(*) FROM review.course_run_records WHERE run_record_id=? AND NOT deleted",s.id())).isZero();
        assertThat(count("SELECT count(*) FROM ranking.distance_run_records WHERE member_id=?",s.owner())).isOne();
    }

    private void linkedCopies(Source s,GpsCourseRegisteredEvent e) {
        await().atMost(Duration.ofSeconds(15)).untilAsserted(()-> {
            assertThat(links.status(s.owner(),s.id()).status()).isEqualTo("LINKED");
            assertThat(count("SELECT count(*) FROM ranking.course_ranking_entries WHERE run_record_id=? AND NOT deleted",s.id())).isOne();
            assertThat(count("SELECT count(*) FROM review.course_run_records WHERE run_record_id=? AND NOT deleted",s.id())).isOne();
            assertThat(db.queryForObject("SELECT completion_count FROM course.course_stats WHERE course_id=?",Integer.class,e.courseId())).isOne();
        });
    }
    private long count(String query,UUID id) {return db.queryForObject(query,Long.class,id);}
    private String saved(UUID id) {return db.queryForObject("SELECT result_json FROM run.records WHERE id=?",String.class,id);}
    private String raw(UUID id) {return String.join("\n",db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",(r,n)->r.getString(1),id));}
    private void publish(Object event) {tx.executeWithoutResult(s->events.publishEvent(event));}
    private void drain() {
        await().atMost(Duration.ofSeconds(15)).untilAsserted(()->assertThat(db.queryForObject("SELECT count(*) FROM common.event_publication",Long.class)).isZero());
    }
}
