package com.wadadak.run.internal.recording;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.*;
import com.wadadak.event.run.CourseActiveRunnersChangedEvent;
import com.wadadak.event.run.CourseRunStartedEvent;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.concurrent.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.modulith.test.AssertablePublishedEvents;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Isolated PostGIS: persist a source, approve a duel, retry/read/delete using real run transactions. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class GhostStartTest {
    @Autowired CourseRunService courses;
    @Autowired RunService runs;
    @Autowired GhostStartService starts;
    @Autowired GhostStartStore store;
    @Autowired JdbcTemplate db;
    @Autowired MockMvc mvc;
    @Autowired JsonMapper json;
    @Autowired PlatformTransactionManager transactions;
    @MockitoBean CourseApi courseApi;
    @MockitoBean GpsGapWorker gpsGapWorker; // 1분마다 끊긴 구간 판단을 채우는 작업이 테스트 중에 돌지 않게
    @MockitoBean RunProcessingWorker processingWorker;
    @MockitoBean CourseRunReleaseWorker releaseWorker;

    final UUID owner = UUID.randomUUID(), source = UUID.randomUUID(), id = UUID.randomUUID(), courseId = UUID.randomUUID();
    final Instant sourceStart = Instant.parse("2026-10-26T00:00:00Z");
    final Instant start = Instant.now().truncatedTo(ChronoUnit.MICROS);
    CourseRouteSnapshot current;

    @BeforeEach void setup() throws Exception {
        for (String table : List.of("course_attempts", "course_runner_counts", "withdrawn_members",
                "deleted_records", "records", "inputs", "sessions")) db.update("DELETE FROM run." + table);
        var fixture = json.readTree(Files.readString(Path.of("../run/fixtures/ghost_playback_v1.json")));
        List<GeoPoint> route = new ArrayList<>();
        for (var p : fixture.get("route")) route.add(json.treeToValue(p, GeoPoint.class));
        current = new CourseRouteSnapshot(courseId, "합성 코스", route, 1000, 3);
        when(courseApi.getRouteForRun(any())).thenReturn(current);
        List<Input> raw = new ArrayList<>();
        for (var p : fixture.get("cases").get(1).get("inputs")) raw.add(json.treeToValue(p, Input.class));
        courses.prepare(owner, source, courseId);
        courses.start(owner, source, sourceStart);
        runs.prepare(owner, source, new Prepare(sourceStart, "COURSE"));
        runs.upload(owner, source, new Upload(raw.size() - 1, raw));
        runs.process(source);
        assertThat(runs.status(owner, source).processing()).isEqualTo("DONE");
        courses.prepare(owner, id, courseId);
        clearInvocations(courseApi);
    }

    GhostStart request() { return new GhostStart(courseId, 3L, source, start, "GHOST_PLAYBACK_V1"); }
    String url() { return "/api/v1/runs/sessions/" + id + "/ghost/start"; }
    long count(String table) { return db.queryForObject("SELECT count(*) FROM run." + table, Long.class); }
    void error(Runnable action, Object expected) {
        assertThatThrownBy(action::run).isInstanceOfSatisfying(AppException.class,
                e -> assertThat(e.getErrorCode()).isEqualTo(expected));
    }
    void notStarted() {
        assertThat(count("ghost_starts")).isZero();
        assertThat(count("ghost_start_playbacks")).isZero();
        assertThat(db.queryForObject("SELECT started_at FROM run.course_attempts WHERE session_id=?", Instant.class, id)).isNull();
    }

    @Test void approvalApiRechecksCourseOutsideWriteTransactionAndRetriesPublishOnlyOneStart(AssertablePublishedEvents events) throws Exception {
        String sourceResult = db.queryForObject("SELECT result_json FROM run.records WHERE id=?", String.class, source);
        when(courseApi.getRouteForRun(courseId)).thenAnswer(call -> {
            assertThat(TransactionSynchronizationManager.isActualTransactionActive()).isFalse();
            return current;
        });
        var response = mvc.perform(post(url()).with(jwt().jwt(j -> j.subject(owner.toString())))
                        .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(request())))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.version").value("GHOST_START_V1"))
                .andExpect(jsonPath("$.data.sessionId").value(id.toString()))
                .andExpect(jsonPath("$.data.sourceRecordId").value(source.toString()))
                .andExpect(jsonPath("$.data.playback.eligible").value(true))
                .andExpect(jsonPath("$.data.playback.durationMs").value(230000)).andReturn().getResponse();
        var approved = json.treeToValue(json.readTree(response.getContentAsString()).get("data"), GhostStartApproval.class);
        assertThat(starts.start(owner, id, request())).isEqualTo(approved);
        assertThat(store.get(owner, id)).isEqualTo(approved);
        // A fresh repository also reads the durable receipt; there is no in-memory approval cache.
        assertThat(new GhostStartRepository(db, json).find(id)).contains(approved);
        courses.start(owner, id, start); // Old F6 retry is also harmless.
        assertThat(events.ofType(CourseRunStartedEvent.class).matching(e -> e.runSessionId().equals(id))).hasSize(1);
        assertThat(events.ofType(CourseActiveRunnersChangedEvent.class).matching(e -> e.activeCount() == 1)).hasSize(1);
        assertThat(count("ghost_starts")).isEqualTo(1);
        verify(courseApi, times(1)).getRouteForRun(courseId);
        assertThat(db.queryForObject("SELECT result_json FROM run.records WHERE id=?", String.class, source)).isEqualTo(sourceResult);
        mvc.perform(get(url()).with(jwt().jwt(j -> j.subject(owner.toString()))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.approvedAt").value(approved.approvedAt().toString()));
        Path evidence = Path.of("build/ghost-start-check/approved-own-ghost.json");
        Files.createDirectories(evidence.getParent());
        Files.writeString(evidence, response.getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
    }

    @Test void concurrentIdenticalStartsReturnTheSameDurableReceipt(AssertablePublishedEvents events) throws Exception {
        CountDownLatch ready = new CountDownLatch(2), go = new CountDownLatch(1);
        when(courseApi.getRouteForRun(courseId)).thenAnswer(call -> {
            ready.countDown();
            if (!go.await(10, TimeUnit.SECONDS)) throw new IllegalStateException("test barrier timeout");
            return current;
        });
        try (var workers = Executors.newFixedThreadPool(2)) {
            var first = workers.submit(() -> starts.start(owner, id, request()));
            var second = workers.submit(() -> starts.start(owner, id, request()));
            assertThat(ready.await(10, TimeUnit.SECONDS)).isTrue();
            go.countDown();
            assertThat(first.get(10, TimeUnit.SECONDS)).isEqualTo(second.get(10, TimeUnit.SECONDS));
        } finally { go.countDown(); }
        assertThat(count("ghost_starts")).isEqualTo(1);
        assertThat(count("ghost_start_playbacks")).isEqualTo(1);
        assertThat(events.ofType(CourseRunStartedEvent.class).matching(e -> e.runSessionId().equals(id))).hasSize(1);
    }

    @Test void retryAndGetKeepTheFixedReplayAfterSourceDeletionAndCourseBecomesUnavailable() {
        var approved = starts.start(owner, id, request());
        runs.delete(owner, source);
        when(courseApi.getRouteForRun(any())).thenThrow(new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE));
        clearInvocations(courseApi);
        assertThat(starts.start(owner, id, request())).isEqualTo(approved);
        assertThat(store.get(owner, id)).isEqualTo(approved);
        assertThat(count("records")).isZero();
        assertThat(count("inputs")).isZero();
        verifyNoInteractions(courseApi);
    }

    @Test void modifiedRetryCannotSwitchOpponentTimeCourseVersionOrPlayback() {
        var approved = starts.start(owner, id, request());
        for (var request : List.of(
                new GhostStart(courseId, 3L, UUID.randomUUID(), start, "GHOST_PLAYBACK_V1"),
                new GhostStart(courseId, 3L, source, start.plusSeconds(1), "GHOST_PLAYBACK_V1"),
                new GhostStart(UUID.randomUUID(), 3L, source, start, "GHOST_PLAYBACK_V1"),
                new GhostStart(courseId, 4L, source, start, "GHOST_PLAYBACK_V1"),
                new GhostStart(courseId, 3L, source, start, "GHOST_PLAYBACK_V2")))
            error(() -> starts.start(owner, id, request), RunErrorCode.CONFLICT);
        assertThat(store.get(owner, id)).isEqualTo(approved);
    }

    @Test void courseUnavailableAfterPreparationCannotApprove() {
        when(courseApi.getRouteForRun(any())).thenThrow(new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE));
        error(() -> starts.start(owner, id, request()), CourseErrorCode.COURSE_NOT_AVAILABLE);
        notStarted();
    }

    @Test void changedCurrentVersionRouteDistanceOrIdentityCannotApprove() {
        List<CourseRouteSnapshot> changed = List.of(
                new CourseRouteSnapshot(courseId, "코스", current.route(), 1000, 4),
                new CourseRouteSnapshot(courseId, "코스", current.route().reversed(), 1000, 3),
                new CourseRouteSnapshot(courseId, "코스", current.route(), 999, 3),
                new CourseRouteSnapshot(UUID.randomUUID(), "코스", current.route(), 1000, 3));
        for (var course : changed) {
            when(courseApi.getRouteForRun(any())).thenReturn(course);
            error(() -> starts.start(owner, id, request()), RunErrorCode.CONFLICT);
            notStarted();
        }
    }

    @Test void differentSourceCourseVersionCannotApproveEvenWhenItsReplayIsValid() {
        db.update("UPDATE run.course_attempts SET course_version=4 WHERE session_id=?", id);
        when(courseApi.getRouteForRun(any())).thenReturn(new CourseRouteSnapshot(courseId, "코스", current.route(), 1000, 4));
        error(() -> starts.start(owner, id, new GhostStart(courseId, 4L, source, start, "GHOST_PLAYBACK_V1")), RunErrorCode.CONFLICT);
        notStarted();
    }

    @Test void missingOrDeletedSourceCannotApproveAndDoesNotIncrementRunners() {
        error(() -> starts.start(owner, id, new GhostStart(courseId, 3L, UUID.randomUUID(), start, "GHOST_PLAYBACK_V1")), RunErrorCode.NOT_FOUND);
        runs.delete(owner, source);
        error(() -> starts.start(owner, id, request()), RunErrorCode.NOT_FOUND);
        notStarted();
    }

    @Test void sourceDeletionDuringExternalCheckWinsBeforeTheApprovalTransaction() {
        when(courseApi.getRouteForRun(any())).thenAnswer(call -> {
            runs.delete(owner, source);
            return current;
        });
        error(() -> starts.start(owner, id, request()), RunErrorCode.NOT_FOUND);
        notStarted();
    }

    @Test void missingSourceInputCannotApproveAndLeavesTheConfirmedSourceUnchanged() {
        String before = db.queryForObject("SELECT result_json FROM run.records WHERE id=?", String.class, source);
        db.update("DELETE FROM run.inputs WHERE session_id=? AND stream_seq=3", source);
        error(() -> starts.start(owner, id, request()), RunErrorCode.GHOST_UNAVAILABLE);
        notStarted();
        assertThat(db.queryForObject("SELECT result_json FROM run.records WHERE id=?", String.class, source)).isEqualTo(before);
    }

    @Test void otherOwnerCannotReadApproveOrUseSomeoneElsesSource() throws Exception {
        UUID stranger = UUID.randomUUID(), foreign = UUID.randomUUID();
        mvc.perform(post(url()).with(jwt().jwt(j -> j.subject(stranger.toString())))
                .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(request())))
                .andExpect(status().isNotFound());
        courses.prepare(stranger, foreign, courseId);
        error(() -> starts.start(stranger, foreign, request()), RunErrorCode.NOT_FOUND);
        starts.start(owner, id, request());
        mvc.perform(get(url()).with(jwt().jwt(j -> j.subject(stranger.toString())))).andExpect(status().isNotFound());
    }

    @Test void unpreparedSessionAndPendingApprovalReturnNotFound() throws Exception {
        mvc.perform(get(url()).with(jwt().jwt(j -> j.subject(owner.toString())))).andExpect(status().isNotFound());
        error(() -> starts.start(owner, UUID.randomUUID(), request()), RunErrorCode.NOT_FOUND);
        notStarted();
    }

    @Test void ordinaryStartedOrAlreadyUploadedSessionCannotBecomeAGhostDuel() {
        courses.start(owner, id, start);
        error(() -> starts.start(owner, id, request()), RunErrorCode.CONFLICT);
        error(() -> starts.start(owner, source, new GhostStart(courseId, 3L, id, sourceStart, "GHOST_PLAYBACK_V1")), RunErrorCode.CONFLICT);
        assertThat(count("ghost_starts")).isZero();
    }

    @Test void ownDeletionClearsApprovalAndDetailAndPreventsResurrection() {
        starts.start(owner, id, request());
        runs.delete(owner, id); // Before any upload/session exists.
        error(() -> starts.start(owner, id, request()), RunErrorCode.NOT_FOUND);
        error(() -> store.get(owner, id), RunErrorCode.NOT_FOUND);
        assertThat(count("ghost_starts")).isZero();
        assertThat(count("ghost_start_playbacks")).isZero();
    }

    @Test void otherOwnerCannotDeletePreparedOrApprovedUnuploadedDuels() {
        UUID stranger = UUID.randomUUID();
        error(() -> runs.delete(stranger, id), RunErrorCode.NOT_FOUND);
        var approved = starts.start(owner, id, request());
        error(() -> runs.delete(stranger, id), RunErrorCode.NOT_FOUND);
        assertThat(store.get(owner, id)).isEqualTo(approved);
        assertThat(count("deleted_records")).isZero();
    }

    @Test void withdrawalClearsAllApprovalsIncludingUnuploadedDuels() {
        starts.start(owner, id, request());
        runs.withdraw(owner, start.plusSeconds(1));
        error(() -> starts.start(owner, id, request()), RunErrorCode.NOT_FOUND);
        error(() -> store.get(owner, id), RunErrorCode.NOT_FOUND);
        assertThat(count("ghost_starts")).isZero();
        assertThat(count("ghost_start_playbacks")).isZero();
    }

    @Test void deletionOfTheDuelDuringExternalValidationCannotRecreateIt() {
        when(courseApi.getRouteForRun(any())).thenAnswer(call -> {
            runs.delete(owner, id);
            return current;
        });
        error(() -> starts.start(owner, id, request()), RunErrorCode.NOT_FOUND);
        assertThat(count("ghost_starts")).isZero();
    }

    @Test void transactionRollbackDoesNotLeaveApprovalDetailOrStartCounter() {
        var template = new TransactionTemplate(transactions);
        assertThatThrownBy(() -> template.executeWithoutResult(tx -> {
            store.approve(owner, id, request(), current, start);
            throw new IllegalStateException("simulated failure before commit");
        })).isInstanceOf(IllegalStateException.class);
        notStarted();
        assertThat(db.queryForObject("SELECT version FROM run.course_runner_counts WHERE course_id=?", Long.class, courseId)).isEqualTo(2);
        assertThat(starts.start(owner, id, request()).sessionId()).isEqualTo(id);
    }

    @Test void invalidBodyUnsupportedPlaybackSelfReferenceAndSubMicrosecondTimesAreRejected() throws Exception {
        for (String body : List.of("{}", json.writeValueAsString(request()).replace("\"courseVersion\":3,", ""), json.writeValueAsString(new GhostStart(courseId, -1L, source, start, "GHOST_PLAYBACK_V1")),
                json.writeValueAsString(new GhostStart(courseId, 3L, source, start, "UNKNOWN")))) {
            mvc.perform(post(url()).with(jwt().jwt(j -> j.subject(owner.toString())))
                    .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isBadRequest());
        }
        error(() -> starts.start(owner, id, new GhostStart(courseId, 3L, id, start, "GHOST_PLAYBACK_V1")), RunErrorCode.INVALID);
        error(() -> starts.start(owner, id, new GhostStart(courseId, 3L, source, start.plusNanos(1), "GHOST_PLAYBACK_V1")), RunErrorCode.INVALID);
        error(() -> starts.start(owner, id, new GhostStart(courseId, 3L, source, Instant.now().plusSeconds(600), "GHOST_PLAYBACK_V1")), RunErrorCode.INVALID);
        notStarted();
    }

    @Test void initialJpaCourseVersionZeroIsAValidStartContext() throws Exception {
        Result stored = json.readValue(db.queryForObject("SELECT result_json FROM run.records WHERE id=?", String.class, source), Result.class);
        CourseOutcome c = stored.course();
        CourseOutcome zero = new CourseOutcome(c.courseId(), c.courseName(), 0, c.courseDistanceMeters(),
                c.completed(), c.reason(), c.recognizedDistanceMeters(), c.progressPercent(), c.completedAt(),
                c.courseElapsedSeconds(), c.courseMovingSeconds(), c.reviewEligible());
        Result result = new Result(stored.id(), stored.startedAt(), stored.endedAt(), stored.registeredAt(),
                stored.endReason(), stored.metrics(), stored.routeSegments(), stored.laps(), stored.policyVersion(),
                stored.calculationVersion(), stored.stats(), zero);
        db.update("UPDATE run.records SET result_json=? WHERE id=?", json.writeValueAsString(result), source);
        db.update("UPDATE run.course_attempts SET course_version=0 WHERE session_id IN (?, ?)", source, id);
        when(courseApi.getRouteForRun(any())).thenReturn(new CourseRouteSnapshot(courseId, "코스", current.route(), 1000, 0));
        mvc.perform(post(url()).with(jwt().jwt(j -> j.subject(owner.toString())))
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(new GhostStart(courseId, 0L, source, start, "GHOST_PLAYBACK_V1"))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.data.course.version").value(0));
    }

    @Test void requestsRequireAuthentication() throws Exception {
        mvc.perform(get(url())).andExpect(status().isUnauthorized());
        mvc.perform(post(url()).contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(request())))
                .andExpect(status().isUnauthorized());
    }
}
