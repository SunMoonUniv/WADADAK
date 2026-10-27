package com.wadadak.run.internal.recording;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.run.internal.RunContracts.*;
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
import tools.jackson.databind.json.JsonMapper;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Isolated PostGIS only: persist an uploaded source, then replay the persisted record. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class GhostPlaybackIntegrationTest {
    @Autowired CourseRunService courses;
    @Autowired RunService runs;
    @Autowired GhostPlaybackService playback;
    @Autowired JdbcTemplate db;
    @Autowired MockMvc mvc;
    @Autowired JsonMapper json;
    @MockitoBean CourseApi courseApi;
    @MockitoBean GpsGapWorker gpsGapWorker; // 1분마다 끊긴 구간 판단을 채우는 작업이 테스트 중에 돌지 않게
    @MockitoBean RunProcessingWorker processingWorker;
    @MockitoBean CourseRunReleaseWorker releaseWorker;
    final UUID owner = UUID.randomUUID(), id = UUID.randomUUID(), courseId = UUID.randomUUID();
    final Instant start = Instant.parse("2026-10-26T00:00:00Z");

    @BeforeEach void setup() throws Exception {
        for (String table : List.of("course_attempts", "course_runner_counts", "withdrawn_members",
                "deleted_records", "records", "inputs", "sessions")) db.update("DELETE FROM run." + table);
        var fixture = json.readTree(Files.readString(Path.of("../run/fixtures/ghost_playback_v1.json")));
        List<GeoPoint> route = new ArrayList<>();
        for (var p : fixture.get("route")) route.add(json.treeToValue(p, GeoPoint.class));
        when(courseApi.getRouteForRun(any())).thenReturn(new CourseRouteSnapshot(courseId, "합성 코스", route, 1000, 3));
    }

    List<Input> fixture(int index) throws Exception {
        var fixture = json.readTree(Files.readString(Path.of("../run/fixtures/ghost_playback_v1.json")));
        List<Input> raw = new ArrayList<>();
        for (var input : fixture.get("cases").get(index).get("inputs")) raw.add(json.treeToValue(input, Input.class));
        return raw;
    }

    void save(List<Input> raw, boolean course) {
        if (course) {
            courses.prepare(owner, id, courseId);
            courses.start(owner, id, start);
        }
        runs.prepare(owner, id, new Prepare(start, course ? "COURSE" : "FREE"));
        runs.upload(owner, id, new Upload(raw.size() - 1, raw));
        runs.process(id);
        assertThat(runs.status(owner, id).processing()).isEqualTo("DONE");
    }

    String savedResult() { return db.queryForObject("SELECT result_json FROM run.records WHERE id=?", String.class, id); }
    String savedInputs() {
        return String.join("\n", db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",
                (rs, n) -> rs.getString(1), id));
    }

    @Test void persistedOwnCompletedRunReplaysPauseAndPreservesAllStoredDataOnRepeatedReads() throws Exception {
        save(fixture(1), true);
        String result = savedResult(), inputs = savedInputs();
        String summary = db.queryForObject("SELECT summary_json FROM run.records WHERE id=?", String.class, id);
        var response = mvc.perform(get("/api/v1/runs/records/" + id + "/ghost-playback")
                        .with(jwt().jwt(j -> j.subject(owner.toString()))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.version").value("GHOST_PLAYBACK_V1"))
                .andExpect(jsonPath("$.data.eligible").value(true))
                .andExpect(jsonPath("$.data.durationMs").value(230000))
                .andExpect(jsonPath("$.data.quality.gapMs").value(0))
                .andExpect(jsonPath("$.data.spans[1].state").value("PAUSED"))
                .andExpect(jsonPath("$.data.spans[1].fromMs").value(40000))
                .andExpect(jsonPath("$.data.spans[1].toMs").value(70000))
                .andReturn().getResponse();
        Path evidence = Path.of("build/ghost-playback-check/own-completed-record.json");
        Files.createDirectories(evidence.getParent());
        Files.writeString(evidence, response.getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
        GhostPlayback first = playback.own(owner, id);
        assertThat(playback.own(owner, id)).isEqualTo(first);
        assertThat(savedResult()).isEqualTo(result);
        assertThat(savedInputs()).isEqualTo(inputs);
        assertThat(db.queryForObject("SELECT summary_json FROM run.records WHERE id=?", String.class, id)).isEqualTo(summary);
    }

    @Test void gapsDuringPauseKeepCourseCompletionAndGhostReplayAfterUploadAndRetry(
            org.springframework.modulith.test.AssertablePublishedEvents events) throws Exception {
        var original = fixture(1);
        var baseline = com.wadadak.run.internal.metrics.FreeRunCalculator.calculate(start, original);
        var raw = new ArrayList<Input>();
        for (var p : original) {
            if (p.kind() == Kind.RESUME) {
                raw.add(new Input(raw.size(), Kind.GAP, 45000, start.plusMillis(45000), null, null, "GPS_UNAVAILABLE"));
                raw.add(new Input(raw.size(), Kind.GAP, 46000, start.plusMillis(46000), null, null, "GPS_UNAVAILABLE"));
            }
            raw.add(new Input(raw.size(), p.kind(), p.elapsedMs(), p.measuredAt(), p.location(), p.accuracyM(),
                    p.reason(), p.speedMps(), p.speedAccuracyMps(), p.steps(), p.durationMs(), p.sampleEndMs(),
                    p.altitudeM(), p.altitudeAccuracyM(), p.pressureHpa(), p.pressureAccuracy()));
        }
        save(raw, true);
        var stored = runs.result(owner, id);
        assertThat(stored.metrics()).isEqualTo(baseline.metrics());
        assertThat(stored.routeSegments()).isEqualTo(baseline.segments());
        assertThat(stored.laps()).isEqualTo(baseline.laps());
        assertThat(stored.calculationVersion()).isEqualTo("PACE_V3");
        assertThat(stored.course().completed()).isTrue();
        var ghost = playback.own(owner, id);
        assertThat(ghost.eligible()).isTrue();
        assertThat(ghost.durationMs()).isEqualTo(230000);
        assertThat(ghost.quality().gapMs()).isZero();
        assertThat(ghost.spans()).anySatisfy(span -> {
            assertThat(span.state()).isEqualTo(GhostSpanState.PAUSED);
            assertThat(span.fromMs()).isEqualTo(40000);
            assertThat(span.toMs()).isEqualTo(70000);
        });
        String result = savedResult(), inputs = savedInputs();
        runs.upload(owner, id, new Upload(raw.size() - 1, raw)); runs.process(id);
        assertThat(runs.result(owner, id)).isEqualTo(stored);
        assertThat(savedResult()).isEqualTo(result);
        assertThat(savedInputs()).isEqualTo(inputs);
        assertThat(playback.own(owner, id)).isEqualTo(ghost);
        assertThat(events.ofType(com.wadadak.event.run.RunSessionEndedEvent.class)).hasSize(1);
    }

    @Test void candidateSelectionFetchesOnlyTheSelectedPersistedReplayAndLeavesSourceUnchanged() throws Exception {
        save(fixture(1), true);
        String beforeResult = savedResult(), beforeInputs = savedInputs();
        var response = mvc.perform(get("/api/v1/runs/ghost-candidates/own")
                .param("courseId", courseId.toString()).param("courseVersion", "3")
                .with(jwt().jwt(j -> j.subject(owner.toString()))))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.content[0].id").value(id.toString()))
            .andExpect(jsonPath("$.data.summary.best.id").value(id.toString()))
            .andReturn().getResponse();
        var page = json.treeToValue(json.readTree(response.getContentAsString()).get("data"), OwnGhostCandidatePage.class);
        var selected = page.content().getFirst();
        assertThat(selected.courseElapsedSeconds()).isEqualTo(230);
        var replay = mvc.perform(get("/api/v1/runs/records/" + selected.id() + "/ghost-playback")
                .with(jwt().jwt(j -> j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.eligible").value(true))
            .andReturn().getResponse();
        Path folder = Path.of("build/ghost-playback-check");
        Files.createDirectories(folder);
        Files.writeString(folder.resolve("own-candidates.json"), response.getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
        Files.writeString(folder.resolve("selected-own-replay.json"), replay.getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
        assertThat(savedResult()).isEqualTo(beforeResult);
        assertThat(savedInputs()).isEqualTo(beforeInputs);
    }

    @Test void mainCourseSourceAndGhostReplayCoexistWithoutChangingTheRecordedRoute() throws Exception {
        save(fixture(1), true);
        String storedResult = savedResult(), storedInputs = savedInputs();
        var source = runs.courseSource(owner, id);
        var result = runs.result(owner, id);
        assertThat(source.recordId()).isEqualTo(id);
        assertThat(source.distanceMeters()).isEqualTo(result.metrics().distanceM());
        assertThat(source.segments().stream().map(s -> s.stream().map(p -> new GeoPoint(p.lat(), p.lng())).toList()).toList())
            .isEqualTo(result.routeSegments());
        mvc.perform(get("/api/v1/runs/records/" + id + "/course-source")
                .with(jwt().jwt(j -> j.subject(owner.toString()))))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.recordId").value(id.toString()))
            .andExpect(jsonPath("$.data.segments").isNotEmpty());
        assertThat(playback.own(owner, id).eligible()).isTrue();
        assertThat(runs.courseSource(owner, id)).isEqualTo(source);
        assertThat(savedResult()).isEqualTo(storedResult);
        assertThat(savedInputs()).isEqualTo(storedInputs);
    }

    @Test void otherOwnerMissingAndDeletedRecordsCannotBeRead() throws Exception {
        save(fixture(0), true);
        mvc.perform(get("/api/v1/runs/records/" + id + "/ghost-playback")
                .with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString())))).andExpect(status().isNotFound());
        mvc.perform(get("/api/v1/runs/records/" + UUID.randomUUID() + "/ghost-playback")
                .with(jwt().jwt(j -> j.subject(owner.toString())))).andExpect(status().isNotFound());
        runs.delete(owner, id);
        mvc.perform(get("/api/v1/runs/records/" + id + "/ghost-playback")
                .with(jwt().jwt(j -> j.subject(owner.toString())))).andExpect(status().isNotFound());
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?", Long.class, id)).isZero();
    }

    @Test void missingSourceInputReturnsUnavailableWithoutChangingCompletion() throws Exception {
        save(fixture(0), true);
        String result = savedResult();
        db.update("DELETE FROM run.inputs WHERE session_id=? AND stream_seq=3", id);
        assertThat(playback.own(owner, id).unavailableReasons()).containsExactly("MISSING_SOURCE_INPUTS");
        assertThat(savedResult()).isEqualTo(result);
        assertThat(runs.result(owner, id).course().completed()).isTrue();
    }

    @Test void missingSnapshotIsUnavailableAndDoesNotFetchCurrentCourse() throws Exception {
        save(fixture(0), true);
        String result = savedResult();
        db.update("DELETE FROM run.course_attempts WHERE session_id=?", id);
        assertThat(playback.own(owner, id).unavailableReasons()).containsExactly("MISSING_COURSE_SNAPSHOT");
        assertThat(savedResult()).isEqualTo(result);
    }

    @Test void ownFreeRecordIsNotAnEligibleCourseGhost() throws Exception {
        save(fixture(0), false);
        mvc.perform(get("/api/v1/runs/records/" + id + "/ghost-playback")
                        .with(jwt().jwt(j -> j.subject(owner.toString()))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.eligible").value(false))
                .andExpect(jsonPath("$.data.unavailableReasons[0]").value("NOT_COMPLETED"));
    }

    @Test void courseReplayExcludesFreeRunningAndDoesNotBridgeUnknownGps() throws Exception {
        save(fixture(2), true);
        GhostPlayback result = playback.own(owner, id);
        assertThat(result.eligible()).isTrue();
        assertThat(result.durationMs()).isEqualTo(1940000);
        assertThat(result.spans().getFirst().state()).isEqualTo(GhostSpanState.UNKNOWN);
        assertThat(result.spans().getLast().toMs()).isEqualTo(1940000);
        assertThat(result.spans().getLast().toPositionM()).isCloseTo(970, within(1e-6));
        assertThat(runs.result(owner, id).metrics().elapsedMs()).isGreaterThan(result.durationMs());
    }
}
