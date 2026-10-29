package com.wadadak.run.internal.recording;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.RunContracts.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.any;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class OwnGhostCandidatesTest {
    @org.springframework.test.context.bean.override.mockito.MockitoBean com.wadadak.ranking.RankingApi rankingApi;
    @Autowired OwnGhostCandidates candidates;
    @Autowired JdbcTemplate db;
    @Autowired JsonMapper json;
    @Autowired MockMvc mvc;
    @MockitoBean CourseApi courseApi;
    @MockitoBean GpsGapWorker gpsGapWorker; // 1분마다 끊긴 구간 판단을 채우는 작업이 테스트 중에 돌지 않게
    @MockitoBean RunProcessingWorker processingWorker;
    @MockitoBean CourseRunReleaseWorker releaseWorker;
    @MockitoBean Clock clock;
    UUID owner, courseId;
    JsonNode fixture;

    @BeforeEach void setup() throws Exception {
        for (String table : List.of("course_attempts","course_runner_counts","withdrawn_members","deleted_records","records","inputs","sessions"))
            db.update("DELETE FROM run." + table);
        when(clock.instant()).thenReturn(Instant.parse("2026-10-26T07:00:00Z"));
        when(clock.withZone(ZoneId.of("Asia/Seoul"))).thenReturn(Clock.fixed(Instant.parse("2026-10-26T07:00:00Z"), ZoneId.of("Asia/Seoul")));
        fixture=json.readTree(Files.readString(Path.of("../run/fixtures/own_ghost_candidates_v1.json")));
        owner=UUID.fromString(fixture.get("owner").asText());
        courseId=UUID.fromString(fixture.get("course").get("courseId").asText());
        when(courseApi.getRouteForRun(any())).thenAnswer(call -> new CourseRouteSnapshot(call.getArgument(0),"합성 코스",route(),5200,3));
        for (var row:fixture.get("records")) {
            UUID id=insert(row, owner, courseId, 3, true, "DONE");
            db.update("INSERT INTO run.course_attempts(session_id,member_id,course_id,course_name,course_version,route_json,total_distance_meters) VALUES (?,?,?,'합성 코스',3,?,5200)",
                id,owner,courseId,json.writeValueAsString(route()));
        }
    }
    List<GeoPoint> route() { return List.of(new GeoPoint(36,127),new GeoPoint(36.0468,127)); }

    UUID insert(JsonNode row, UUID member, UUID course, long version, boolean completed, String processing) throws Exception {
        UUID id=UUID.fromString(row.get("id").asText());
        var outcome=new CourseOutcome(course,"합성 코스",version,5200,completed,completed?"COMPLETED":"DISTANCE_SHORT",
            completed?5200:100,completed?100:2,Instant.parse(row.get("completedAt").asText()),
            row.get("courseElapsedSeconds").asLong(),0,completed);
        Double cadence=row.get("averageCadence").isNull()?null:row.get("averageCadence").asDouble();
        var result=new Result(id,Instant.parse(row.get("startedAt").asText()),outcome.completedAt(),
            Instant.parse(row.get("registeredAt").asText()),"USER",new Metrics(5200,2000000,2000000,0,null,2000000,null,cadence,0,0),
            List.of(),List.of(),"2026-10-14","PACE_V3",null,outcome);
        db.update("INSERT INTO run.sessions(id,member_id,started_at,processing) VALUES (?,?,?,?)",
            id,member,java.sql.Timestamp.from(result.startedAt()),processing);
        db.update("INSERT INTO run.records(id,registered_at,result_json,summary_json) VALUES (?,?,?,?)",
            id,java.sql.Timestamp.from(result.registeredAt()),json.writeValueAsString(result),json.writeValueAsString(RecordSummary.from(result)));
        return id;
    }

    List<UUID> ids(String field) {
        var ids=new ArrayList<UUID>();
        for(var value:fixture.get(field)) ids.add(UUID.fromString(value.asText()));
        return ids;
    }
    OwnGhostCandidatePage page(OwnGhostSort sort, OwnGhostPeriod period, String cursor, int size) {
        return candidates.list(owner,courseId,3,sort,period,new Cursorable(cursor,size));
    }

    @Test void recentUsesActualStartAndBestUsesStoredCourseSecondsWithStableTies() {
        assertThat(page(OwnGhostSort.RECENT,OwnGhostPeriod.ALL,null,20).content()).extracting(OwnGhostCandidate::id)
            .containsExactlyElementsOf(ids("recentIds"));
        var best=page(OwnGhostSort.BEST,OwnGhostPeriod.ALL,null,20);
        assertThat(best.content()).extracting(OwnGhostCandidate::id).containsExactlyElementsOf(ids("bestIds"));
        assertThat(best.summary().count()).isEqualTo(6);
        assertThat(best.summary().best().id()).isEqualTo(ids("bestIds").getFirst());
        assertThat(best.summary().averageSeconds()).isCloseTo(fixture.get("page").get("summary").get("averageSeconds").asDouble(),within(.000001));
    }

    @Test void bothSortsPageWithoutDuplicatesOrMissingTiedRecordsAndKeepWholeSummary() {
        for(var sort:OwnGhostSort.values()) {
            var actual=new ArrayList<UUID>();
            String cursor=null;
            do {
                var page=page(sort,OwnGhostPeriod.ALL,cursor,2);
                actual.addAll(page.content().stream().map(OwnGhostCandidate::id).toList());
                assertThat(page.summary().count()).isEqualTo(6);
                cursor=page.nextCursor();
            } while(cursor!=null);
            assertThat(actual).containsExactlyElementsOf(ids(sort==OwnGhostSort.BEST?"bestIds":"recentIds"));
        }
    }

    @Test void periodsUseSeoulStartDateAndExcludeJustBeforeBoundaryDespiteLateRegistration() {
        var week=page(OwnGhostSort.RECENT,OwnGhostPeriod.WEEK,null,20);
        assertThat(week.content()).extracting(OwnGhostCandidate::id).containsExactlyElementsOf(ids("recentIds").subList(0,3));
        assertThat(week.summary().count()).isEqualTo(3);
        var month=page(OwnGhostSort.RECENT,OwnGhostPeriod.MONTH,null,20);
        assertThat(month.content()).extracting(OwnGhostCandidate::id).containsExactlyElementsOf(ids("recentIds").subList(0,5));
        assertThat(month.summary().count()).isEqualTo(5);
    }

    @Test void otherCourseAndVersionNeverReturnThisCoursesOwnedRecords() {
        assertThat(candidates.list(owner,UUID.randomUUID(),3,OwnGhostSort.RECENT,OwnGhostPeriod.ALL,new Cursorable(null,20)).content()).isEmpty();
        assertThatThrownBy(()->candidates.list(owner,courseId,4,OwnGhostSort.RECENT,OwnGhostPeriod.ALL,new Cursorable(null,20)))
            .isInstanceOf(AppException.class);
    }

    @Test void metadataVersionChangeKeepsExactHistoricalRoutesAndWholeSummaryWithoutRewritingSource() {
        var before=db.queryForList("SELECT result_json FROM run.records ORDER BY id");
        when(courseApi.getRouteForRun(courseId)).thenReturn(new CourseRouteSnapshot(courseId,"이름 변경",route(),5200,4));
        var actual=candidates.list(owner,courseId,4,OwnGhostSort.RECENT,OwnGhostPeriod.ALL,new Cursorable(null,2));
        assertThat(actual.summary().count()).isEqualTo(6);
        assertThat(actual.content()).allMatch(c->c.courseVersion()==4);
        assertThat(actual.nextCursor()).isNotNull();
        var next=candidates.list(owner,courseId,4,OwnGhostSort.RECENT,OwnGhostPeriod.ALL,new Cursorable(actual.nextCursor(),20));
        assertThat(next.content()).hasSize(4);
        assertThat(db.queryForList("SELECT result_json FROM run.records ORDER BY id")).isEqualTo(before);
    }

    @Test void historicalCompatibilityRequiresExactOrderedPathDistanceAndSourceSnapshot() {
        when(courseApi.getRouteForRun(courseId)).thenReturn(new CourseRouteSnapshot(courseId,"코스",route().reversed(),5200,4));
        assertThat(candidates.list(owner,courseId,4,OwnGhostSort.RECENT,OwnGhostPeriod.ALL,new Cursorable(null,20)).content()).isEmpty();
        when(courseApi.getRouteForRun(courseId)).thenReturn(new CourseRouteSnapshot(courseId,"코스",route(),5201,4));
        assertThat(candidates.list(owner,courseId,4,OwnGhostSort.RECENT,OwnGhostPeriod.ALL,new Cursorable(null,20)).content()).isEmpty();
        when(courseApi.getRouteForRun(courseId)).thenReturn(new CourseRouteSnapshot(courseId,"코스",route(),5200,4));
        db.update("DELETE FROM run.course_attempts WHERE session_id=?",ids("recentIds").getFirst());
        assertThat(candidates.list(owner,courseId,4,OwnGhostSort.RECENT,OwnGhostPeriod.ALL,new Cursorable(null,20)).summary().count()).isEqualTo(5);
    }

    @Test void excludesForeignFreeIncompleteDifferentVersionDeletedAndProcessingRecords() throws Exception {
        // Move existing valid rows into each excluded state, without creating raw inputs.
        var ids=ids("recentIds");
        db.update("UPDATE run.sessions SET member_id=? WHERE id=?",UUID.randomUUID(),ids.get(0));
        db.update("UPDATE run.records SET result_json=jsonb_set(result_json::jsonb,'{course}','null')::text WHERE id=?",ids.get(1));
        db.update("UPDATE run.records SET result_json=jsonb_set(result_json::jsonb,'{course,completed}','false')::text WHERE id=?",ids.get(2));
        db.update("UPDATE run.records SET result_json=jsonb_set(result_json::jsonb,'{course,courseVersion}','4')::text WHERE id=?",ids.get(3));
        db.update("INSERT INTO run.deleted_records(id,member_id) VALUES (?,?)",ids.get(4),owner);
        db.update("UPDATE run.sessions SET processing='PROCESSING' WHERE id=?",ids.get(5));
        var empty=page(OwnGhostSort.RECENT,OwnGhostPeriod.ALL,null,20);
        assertThat(empty.content()).isEmpty(); assertThat(empty.nextCursor()).isNull();
        assertThat(empty.summary()).isEqualTo(new OwnGhostSummary(0,null,null));
        assertThat(candidates.list(owner,UUID.randomUUID(),3,OwnGhostSort.BEST,OwnGhostPeriod.ALL,new Cursorable(null,20)).content()).isEmpty();
    }

    @Test void malformedOrReusedCursorAndOutOfRangeSizeAreRejected() {
        String cursor=page(OwnGhostSort.RECENT,OwnGhostPeriod.ALL,null,1).nextCursor();
        for(String invalid:List.of("", "broken", cursor.replace("|RECENT|","|BEST|"),
            cursor.replace(courseId.toString(),UUID.randomUUID().toString()),cursor.replace("|ALL|","|MONTH|"),
            cursor.replace("|3|","|4|"),cursor.replace("2026-10-26T00:00:00Z","+1000000000-12-31T23:59:59.999999999Z"))) {
            assertThatThrownBy(()->page(OwnGhostSort.RECENT,OwnGhostPeriod.ALL,invalid,20)).isInstanceOf(AppException.class);
        }
        assertThatThrownBy(()->page(OwnGhostSort.RECENT,OwnGhostPeriod.ALL,null,0)).isInstanceOf(AppException.class);
        assertThatThrownBy(()->page(OwnGhostSort.RECENT,OwnGhostPeriod.ALL,null,51)).isInstanceOf(AppException.class);
    }

    @Test void apiUsesJwtOwnerAndDoesNotExposeRouteOrInputsOrChangeStorage() throws Exception {
        var before=db.queryForList("SELECT * FROM run.records ORDER BY id");
        String body=mvc.perform(get("/api/v1/runs/ghost-candidates/own")
                .param("courseId",courseId.toString()).param("courseVersion","3").param("size","2")
                .with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.content.length()").value(2))
            .andExpect(jsonPath("$.data.summary.count").value(6))
            .andExpect(jsonPath("$.data.content[0].routeSegments").doesNotExist())
            .andExpect(jsonPath("$.data.content[0].inputs").doesNotExist())
            .andReturn().getResponse().getContentAsString();
        assertThat(json.readTree(body).get("data").get("content").get(0).get("id").asText()).isEqualTo(ids("recentIds").getFirst().toString());
        mvc.perform(get("/api/v1/runs/ghost-candidates/own").param("courseId",courseId.toString()).param("courseVersion","3")
                .with(jwt().jwt(j->j.subject(UUID.randomUUID().toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.content").isEmpty());
        assertThat(db.queryForList("SELECT * FROM run.records ORDER BY id")).isEqualTo(before);
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs",Long.class)).isZero();
    }

    @Test void anonymousInvalidParamsAndWithdrawnOwnerCannotReadCandidates() throws Exception {
        mvc.perform(get("/api/v1/runs/ghost-candidates/own").param("courseId",courseId.toString()).param("courseVersion","3"))
            .andExpect(status().isUnauthorized());
        for(String size:List.of("0","51"))
            mvc.perform(get("/api/v1/runs/ghost-candidates/own").param("courseId",courseId.toString()).param("courseVersion","3")
                .param("size",size).with(jwt().jwt(j->j.subject(owner.toString())))).andExpect(status().isBadRequest());
        db.update("INSERT INTO run.withdrawn_members(member_id,withdrawn_at) VALUES (?,now())",owner);
        assertThatThrownBy(()->page(OwnGhostSort.RECENT,OwnGhostPeriod.ALL,null,20)).isInstanceOf(AppException.class);
    }
}
