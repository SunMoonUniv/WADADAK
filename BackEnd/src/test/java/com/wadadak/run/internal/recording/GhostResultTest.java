package com.wadadak.run.internal.recording;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.course.GpsGapCheck;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.modulith.test.AssertablePublishedEvents;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class GhostResultTest {
    @Autowired CourseRunService courses;
    @Autowired RunService runs;
    @Autowired GhostStartService starts;
    @Autowired GhostResultService results;
    @Autowired JdbcTemplate db;
    @Autowired JsonMapper json;
    @Autowired MockMvc mvc;
    @MockitoBean CourseApi courseApi;
    @MockitoBean RunProcessingWorker processingWorker;
    @MockitoBean CourseRunReleaseWorker releaseWorker;
    @MockitoBean GpsGapWorker gpsGapWorker;

    final UUID owner = UUID.randomUUID(), source = UUID.randomUUID(), id = UUID.randomUUID(), courseId = UUID.randomUUID();
    final Instant start = Instant.parse("2026-10-26T01:00:00Z");
    List<Input> normal;
    GhostStartApproval approval;

    @BeforeEach void setup() throws Exception {
        for (String table : List.of("course_attempts", "course_runner_counts", "withdrawn_members",
                "deleted_records", "records", "inputs", "sessions")) db.update("DELETE FROM run." + table);
        var fixture = json.readTree(Files.readString(Path.of("../run/fixtures/ghost_playback_v1.json")));
        List<GeoPoint> route = new ArrayList<>();
        for (var point : fixture.get("route")) route.add(json.treeToValue(point, GeoPoint.class));
        when(courseApi.getRouteForRun(any())).thenReturn(new CourseRouteSnapshot(courseId, "합성 코스", route, 1000, 3));
        normal = new ArrayList<>();
        for (var point : fixture.get("cases").get(0).get("inputs")) normal.add(json.treeToValue(point, Input.class));
        List<Input> paused = new ArrayList<>();
        for (var point : fixture.get("cases").get(1).get("inputs")) paused.add(json.treeToValue(point, Input.class));
        courses.prepare(owner, source, courseId);
        courses.start(owner, source, Instant.parse(fixture.get("startedAt").asText()));
        runs.prepare(owner, source, new Prepare(Instant.parse(fixture.get("startedAt").asText()), "COURSE"));
        runs.upload(owner, source, new Upload(paused.size() - 1, paused));
        runs.process(source);
        courses.prepare(owner, id, courseId);
        approval = starts.start(owner, id, new GhostStart(courseId, 3L, source, start, "GHOST_PLAYBACK_V1"));
        clearInvocations(courseApi);
    }

    Input append(List<Input> raw, Kind kind, long ms, String reason) {
        Input p = new Input(raw.size(), kind, ms, start.plusMillis(ms), null, null, reason);
        raw.add(p); return p;
    }
    List<Input> prefix(boolean completed) {
        List<Input> raw = new ArrayList<>();
        for (Input p : normal) {
            if (p.kind() == Kind.END || p.kind() == Kind.PAUSE || (!completed && p.elapsedMs() > 40000)) continue;
            raw.add(new Input(raw.size(), p.kind(), p.elapsedMs(), start.plusMillis(p.elapsedMs()), p.location(), p.accuracyM(),
                    p.reason(), p.speedMps(), p.speedAccuracyMps(), p.steps(), p.durationMs(), p.sampleEndMs(),
                    p.altitudeM(), p.altitudeAccuracyM(), p.pressureHpa(), p.pressureAccuracy()));
        }
        return raw;
    }
    List<Input> completeAfterPause(long pauseMs) {
        List<Input> raw = prefix(true);
        List<Input> shifted = new ArrayList<>();
        for (Input p : raw) {
            long ms = p.elapsedMs() + (p.kind() == Kind.GPS ? pauseMs : 0);
            if (p.kind() == Kind.START) {
                shifted.add(p);
                if (pauseMs > 0) { append(shifted, Kind.PAUSE, 0, null); append(shifted, Kind.RESUME, pauseMs, "MANUAL"); }
            } else shifted.add(new Input(shifted.size(), p.kind(), ms, start.plusMillis(ms), p.location(), p.accuracyM(), p.reason(),
                    p.speedMps(), p.speedAccuracyMps(), p.steps(), p.durationMs(), p.sampleEndMs(), p.altitudeM(), p.altitudeAccuracyM()));
        }
        append(shifted, Kind.END, 201000 + pauseMs, "INTERRUPTED");
        return shifted;
    }
    void upload(List<Input> raw) {
        runs.prepare(owner, id, new Prepare(start, "COURSE"));
        runs.upload(owner, id, new Upload(raw.size() - 1, raw));
    }
    GhostOutcome process(List<Input> raw) { upload(raw); runs.process(id); return results.get(owner, id); }
    long count() { return db.queryForObject("SELECT count(*) FROM run.ghost_results", Long.class); }
    String url() { return "/api/v1/runs/sessions/" + id + "/ghost/result"; }
    void notFound(UUID member, UUID session) {
        assertThatThrownBy(() -> results.get(member, session)).isInstanceOfSatisfying(AppException.class,
                e -> assertThat(e.getErrorCode()).isEqualTo(RunErrorCode.NOT_FOUND));
    }

    @Test void finalSummaryIsSavedInRecordListAndDedicatedApiExactlyOnce(AssertablePublishedEvents events) throws Exception {
        var outcome = process(completeAfterPause(0));
        assertThat(outcome.outcome()).isEqualTo(GhostVerdict.WIN);
        assertThat(outcome.courseElapsedSeconds()).isEqualTo(200);
        assertThat(outcome.sourceElapsedSeconds()).isEqualTo(230);
        assertThat(outcome.sessionId()).isEqualTo(id);
        assertThat(outcome.finalizedAt()).isAfter(start.plusSeconds(201));
        assertThat(db.queryForList("SELECT column_name FROM information_schema.columns WHERE table_schema='run' AND table_name='ghost_results'", String.class))
                .containsExactlyInAnyOrder("session_id", "finalized_at", "result_json", "created_at", "updated_at");
        assertThat(json.readTree(db.queryForObject("SELECT result_json FROM run.ghost_results WHERE session_id=?", String.class, id))
                .has("detailExpiresAt")).isFalse();
        assertThat(runs.result(owner, id).ghost()).isEqualTo(outcome);
        assertThat(runs.history(owner, new Cursorable(null, null)).content().stream().filter(r -> r.id().equals(id)).findFirst().orElseThrow().ghost()).isEqualTo(outcome);
        assertThat(new GhostResultRepository(db, json).find(id)).contains(outcome);
        runs.process(id); runs.upload(owner, id, new Upload(completeAfterPause(0).size() - 1, completeAfterPause(0)));
        assertThat(results.get(owner, id)).isEqualTo(outcome);
        assertThat(count()).isEqualTo(1);
        assertThat(events.ofType(RunSessionEndedEvent.class).matching(e -> e.runRecordId().equals(id))).hasSize(1);
        verifyNoInteractions(courseApi);
        mvc.perform(get(url()).with(jwt().jwt(j -> j.subject(owner.toString()))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.outcome").value("WIN"))
                .andExpect(jsonPath("$.data.version").value("GHOST_RESULT_V1"))
                .andExpect(jsonPath("$.data.detailExpiresAt").doesNotExist());
        mvc.perform(get("/api/v1/runs/records/" + id).with(jwt().jwt(j -> j.subject(owner.toString()))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.ghost.outcome").value("WIN"));
    }

    @Test void gpsGapRefreshAndLegacyStatsEnrichmentPreserveGhostOutcome() throws Exception {
        var outcome = process(completeAfterPause(0));
        var gap = new GpsGapCheck(true, "GPS_GAP_V1");
        runs.saveGpsGap(id, gap);
        var stored = runs.result(owner, id);
        assertThat(stored.gpsGap()).isEqualTo(gap);
        assertThat(stored.ghost()).isEqualTo(outcome);
        var summary = runs.history(owner, new Cursorable(null, null)).content().stream()
                .filter(r -> r.id().equals(id)).findFirst().orElseThrow();
        assertThat(summary.gpsGap()).isEqualTo(gap);
        assertThat(summary.ghost()).isEqualTo(outcome);

        var legacy = json.readTree(json.writeValueAsString(stored));
        ((tools.jackson.databind.node.ObjectNode) legacy).remove("stats");
        db.update("UPDATE run.records SET result_json=? WHERE id=?", json.writeValueAsString(legacy), id);
        var enriched = runs.result(owner, id);
        assertThat(enriched.stats()).isEqualTo(stored.stats());
        assertThat(enriched.gpsGap()).isEqualTo(gap);
        assertThat(enriched.ghost()).isEqualTo(outcome);
        mvc.perform(get("/api/v1/runs/records/" + id).with(jwt().jwt(j -> j.subject(owner.toString()))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.gpsGap.passed").value(true))
                .andExpect(jsonPath("$.data.ghost.outcome").value("WIN"));

        var changed = new GpsGapCheck(false, "GPS_GAP_V2");
        runs.saveGpsGap(id, changed);
        assertThat(runs.result(owner, id).gpsGap()).isEqualTo(changed);
        assertThat(runs.result(owner, id).ghost()).isEqualTo(outcome);
        var refreshed = runs.history(owner, new Cursorable(null, null)).content().stream()
                .filter(r -> r.id().equals(id)).findFirst().orElseThrow();
        assertThat(refreshed.gpsGap()).isEqualTo(changed);
        assertThat(refreshed.ghost()).isEqualTo(outcome);
        assertThat(results.get(owner, id)).isEqualTo(outcome);
        assertThat(count()).isEqualTo(1);
    }

    @Test void realCourseTimeIncludesPauseAndIgnoresSubsecondDifferenceForDraw() {
        var outcome = process(completeAfterPause(30999));
        assertThat(outcome.outcome()).isEqualTo(GhostVerdict.DRAW);
        assertThat(outcome.courseElapsedSeconds()).isEqualTo(230);
        assertThat(runs.result(owner, id).course().courseMovingSeconds()).isEqualTo(200);
    }

    @Test void laterCompletionLosesDespiteProcessInterruptedEnd() {
        assertThat(process(completeAfterPause(60000)).outcome()).isEqualTo(GhostVerdict.LOSE);
    }

    @Test void courseOnlyBeforeGhostArrivalDoesNotBecomeLossAfterLongFreeRun() {
        var raw = prefix(false);
        append(raw, Kind.SEGMENT_END, 100000, "COURSE_ONLY");
        append(raw, Kind.PAUSE, 400000, null); append(raw, Kind.END, 401000, "USER");
        var outcome = process(raw);
        assertThat(outcome.outcome()).isEqualTo(GhostVerdict.INVALID);
        assertThat(outcome.courseEndElapsedMs()).isEqualTo(100000);
        assertThat(outcome.courseEndReason()).isEqualTo("COURSE_ONLY");
        assertThat(runs.result(owner, id).metrics().elapsedMs()).isEqualTo(401000);
    }

    @Test void courseOnlyAtGhostArrivalLosesAndLaterInterruptedEndCannotChangeIt() {
        var raw = prefix(false);
        append(raw, Kind.SEGMENT_END, 230000, "COURSE_ONLY"); append(raw, Kind.END, 900000, "INTERRUPTED");
        assertThat(process(raw).outcome()).isEqualTo(GhostVerdict.LOSE);
    }

    @Test void voluntarySessionEndWhilePausedAfterGhostFinishLoses() {
        var raw = prefix(false);
        append(raw, Kind.PAUSE, 40000, null); append(raw, Kind.END, 300000, "USER");
        assertThat(process(raw).outcome()).isEqualTo(GhostVerdict.LOSE);
    }

    @Test void interruptedIncompleteAfterGhostFinishIsInvalidAndLateRetryKeepsIt() {
        var raw = prefix(false); append(raw, Kind.END, 900000, "INTERRUPTED");
        var result = process(raw);
        assertThat(result.outcome()).isEqualTo(GhostVerdict.INVALID);
        assertThat(result.reason()).isEqualTo(GhostVerdictReason.INVOLUNTARY_INCOMPLETE);
        runs.process(id);
        assertThat(results.get(owner, id)).isEqualTo(result);
    }

    @Test void appArrivalWithoutServerCompletionCannotBeTreatedAsWinOrVoluntaryLoss() {
        var raw = prefix(false);
        append(raw, Kind.SEGMENT_END, 300000, "ROUTE_END"); append(raw, Kind.END, 900000, "INTERRUPTED");
        var result = process(raw);
        assertThat(result.outcome()).isEqualTo(GhostVerdict.INVALID);
        assertThat(result.reason()).isEqualTo(GhostVerdictReason.FINISH_NOT_CONFIRMED);
    }

    @Test void confirmedCompletionStaysWinAfterFreeRunContinuesLongPastOpponentFinish() {
        var raw = prefix(true);
        append(raw, Kind.SEGMENT_END, 200000, "ROUTE_END"); append(raw, Kind.END, 900000, "PERMISSION_REVOKED");
        var result = process(raw);
        assertThat(result.outcome()).isEqualTo(GhostVerdict.WIN);
        assertThat(result.courseElapsedSeconds()).isEqualTo(200);
        assertThat(runs.result(owner, id).metrics().elapsedMs()).isEqualTo(900000);
    }

    @Test void sourceDeletionAndMissingReplayDetailDoNotChangeFixedOpponentOrVerdict() {
        runs.delete(owner, source);
        db.update("DELETE FROM run.ghost_start_playbacks WHERE session_id=?", id);
        var result = process(completeAfterPause(0));
        assertThat(result.outcome()).isEqualTo(GhostVerdict.WIN);
        assertThat(result.sourceRecordId()).isEqualTo(source);
        assertThat(result.sourceDurationMs()).isEqualTo(approval.playback().durationMs());
        verifyNoInteractions(courseApi);
    }

    @Test void missingUploadHasNoVerdictAndCannotFinalizeEarly() {
        var raw = completeAfterPause(0);
        runs.prepare(owner, id, new Prepare(start, "COURSE"));
        runs.upload(owner, id, new Upload(raw.size() - 1, raw.subList(0, 3)));
        runs.process(id); notFound(owner, id);
        assertThat(count()).isZero();
        assertThat(runs.status(owner, id).processing()).isEqualTo("NEEDS_DATA");
    }

    @Test void malformedStreamDoesNotInventAVerdict() {
        var raw = prefix(false); append(raw, Kind.END, 50000, "UNKNOWN");
        upload(raw); runs.process(id);
        assertThat(runs.status(owner, id).processing()).isEqualTo("FAILED");
        notFound(owner, id); assertThat(count()).isZero();
    }

    @Test void zeroDistanceGhostKeepsInvalidSummaryWithoutCreatingOrdinaryRecord(AssertablePublishedEvents events) {
        var raw = new ArrayList<Input>(); append(raw, Kind.START, 0, "PACE_V3"); append(raw, Kind.END, 0, "INTERRUPTED");
        var result = process(raw);
        assertThat(result.outcome()).isEqualTo(GhostVerdict.INVALID);
        assertThat(result.reason()).isEqualTo(GhostVerdictReason.INVOLUNTARY_INCOMPLETE);
        assertThat(runs.status(owner, id).failure()).isEqualTo("ZERO_DISTANCE");
        assertThat(db.queryForObject("SELECT count(*) FROM run.records WHERE id=?", Long.class, id)).isZero();
        assertThat(events.ofType(RunSessionEndedEvent.class).matching(e -> e.runRecordId().equals(id))).isEmpty();
    }

    @Test void ownerIsolationAuthenticationAndDeletion() throws Exception {
        mvc.perform(get(url())).andExpect(status().isUnauthorized());
        mvc.perform(get(url()).with(jwt().jwt(j -> j.subject(owner.toString())))).andExpect(status().isNotFound());
        process(completeAfterPause(0));
        mvc.perform(get(url()).with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString())))).andExpect(status().isNotFound());
        runs.delete(owner, id); runs.process(id);
        notFound(owner, id); assertThat(count()).isZero();
        assertThatThrownBy(() -> runs.prepare(owner, id, new Prepare(start, "COURSE"))).isInstanceOf(AppException.class);
    }

    @Test void withdrawalCascadesResultAndDetailedPlayback() {
        process(completeAfterPause(0));
        runs.withdraw(owner, Instant.now());
        notFound(owner, id); assertThat(count()).isZero();
        assertThat(db.queryForObject("SELECT count(*) FROM run.ghost_start_playbacks", Long.class)).isZero();
    }

    @Test void concurrentProcessingRegistersAndFinalizesOnlyOnce(AssertablePublishedEvents events) throws Exception {
        upload(completeAfterPause(0));
        try (var workers = Executors.newFixedThreadPool(2)) {
            var a = workers.submit(() -> runs.process(id)); var b = workers.submit(() -> runs.process(id));
            a.get(20, TimeUnit.SECONDS); b.get(20, TimeUnit.SECONDS);
        }
        assertThat(count()).isEqualTo(1);
        assertThat(runs.status(owner, id).processing()).isEqualTo("DONE");
        assertThat(events.ofType(RunSessionEndedEvent.class).matching(e -> e.runRecordId().equals(id))).hasSize(1);
    }

    @Test void laterRecordWriteFailureRollsBackGhostSummaryAndAllowsCleanRetry() {
        upload(completeAfterPause(0));
        db.execute("CREATE FUNCTION run.reject_ghost_record() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'simulated record failure'; END $$");
        db.execute("CREATE TRIGGER reject_ghost_record BEFORE INSERT ON run.records FOR EACH ROW EXECUTE FUNCTION run.reject_ghost_record()");
        try {
            assertThatThrownBy(() -> runs.process(id)).isInstanceOf(RuntimeException.class);
            assertThat(count()).isZero();
            assertThat(runs.status(owner, id).processing()).isEqualTo("PROCESSING");
            assertThat(db.queryForObject("SELECT count(*) FROM run.records WHERE id=?", Long.class, id)).isZero();
        } finally {
            db.execute("DROP TRIGGER reject_ghost_record ON run.records");
            db.execute("DROP FUNCTION run.reject_ghost_record()");
        }
        runs.process(id);
        assertThat(count()).isEqualTo(1);
        assertThat(results.get(owner, id).outcome()).isEqualTo(GhostVerdict.WIN);
    }

    @Test void oldResultJsonWithoutGhostStillDeserializesAndEnrichmentPreservesNewGhost() {
        var result = process(completeAfterPause(0));
        var stored = (tools.jackson.databind.node.ObjectNode) json.readTree(db.queryForObject("SELECT result_json FROM run.records WHERE id=?", String.class, id));
        stored.remove("stats");
        db.update("UPDATE run.records SET result_json=? WHERE id=?", json.writeValueAsString(stored), id);
        assertThat(runs.result(owner, id).ghost()).isEqualTo(result);
        stored.remove("ghost");
        assertThat(json.treeToValue(stored, Result.class).ghost()).isNull();
        assertThat(runs.result(owner, source).ghost()).isNull();
    }
}
