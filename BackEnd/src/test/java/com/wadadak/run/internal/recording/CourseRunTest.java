package com.wadadak.run.internal.recording;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.event.run.CourseActiveRunnersChangedEvent;
import com.wadadak.event.run.CourseRunStartedEvent;
import com.wadadak.event.run.RunRecordDeletedEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.CourseOutcome;
import com.wadadak.run.internal.RunContracts.CourseSnapshot;
import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.RunContracts.Kind;
import com.wadadak.run.internal.RunContracts.Prepare;
import com.wadadak.run.internal.RunContracts.RecordSummary;
import com.wadadak.run.internal.RunContracts.Upload;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.modulith.test.AssertablePublishedEvents;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 코스 러닝 세션(F6 B단계): 준비 → 시작 신호 → 구간 종료 신호·업로드·자동 제외 → 판정 → 이벤트.
 * 코스는 북쪽으로 곧게 1,000m(출발 36.7990, 127.0750).
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseRunTest {

    static final double LAT0 = 36.7990;
    static final double LNG0 = 127.0750;
    /** 위도 1m (R × π / 180으로 나눔) */
    static final double LAT_PER_M = 1 / (GeoPoint.EARTH_RADIUS_M * Math.PI / 180);

    @Autowired CourseRunService courseRuns;
    @Autowired RunService runs;
    @Autowired JdbcTemplate db;
    @Autowired MockMvc mvc;
    @MockitoBean CourseApi courseApi;
    @MockitoBean RunProcessingWorker processingWorker;
    @MockitoBean CourseRunReleaseWorker releaseWorker;

    final UUID owner = UUID.randomUUID();
    final UUID id = UUID.randomUUID();
    final UUID courseId = UUID.randomUUID();
    // 측정 시작은 지금 근처여야 한다(미래 5분 넘으면 INVALID)
    final Instant startedAt = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MILLIS);

    @BeforeEach
    void clean() {
        for (String table : List.of("course_attempts", "course_runner_counts", "withdrawn_members", "deleted_records",
                "records", "inputs", "sessions")) {
            db.update("DELETE FROM run." + table);
        }
        List<GeoPoint> route = List.of(new GeoPoint(LAT0, LNG0), new GeoPoint(LAT0 + 1000 * LAT_PER_M, LNG0));
        when(courseApi.getRouteForRun(any())).thenAnswer(call ->
                new CourseRouteSnapshot(call.getArgument(0), "테스트 코스", route, 1000, 3));
    }

    /** 출발점에서 north(m)까지 5m마다 2초 간격 GPS. START·END 포함, 업로드 계약 그대로 */
    List<Input> runTo(double north) {
        List<Input> inputs = new ArrayList<>();
        inputs.add(new Input(0, Kind.START, 0, startedAt, null, null, null));
        long ms = 0;
        for (double y = 0; y <= north + 1e-9; y += 5) {
            inputs.add(new Input(inputs.size(), Kind.GPS, ms, startedAt.plusMillis(ms),
                    new GeoPoint(LAT0 + y * LAT_PER_M, LNG0), 5.0, null));
            ms += 2000;
        }
        inputs.add(new Input(inputs.size(), Kind.END, ms, startedAt.plusMillis(ms), null, null, "INTERRUPTED"));
        return inputs;
    }

    void startCourse() {
        courseRuns.prepare(owner, id, courseId);
        courseRuns.start(owner, id, startedAt);
    }

    void uploadAndProcess(List<Input> inputs) {
        runs.prepare(owner, id, new Prepare(startedAt, "COURSE"));
        runs.upload(owner, id, new Upload(inputs.size() - 1, inputs));
        runs.process(id);
    }

    static <T> List<T> all(AssertablePublishedEvents events, Class<T> type) {
        List<T> list = new ArrayList<>();
        events.ofType(type).forEach(list::add);
        return list;
    }

    @Test
    void prepareReturnsStoredSnapshotAndRetriesKeepIt() {
        CourseSnapshot first = courseRuns.prepare(owner, id, courseId);

        assertThat(first.courseId()).isEqualTo(courseId);
        assertThat(first.route()).hasSize(2);
        assertThat(first.totalDistanceMeters()).isEqualTo(1000);
        assertThat(courseRuns.prepare(owner, id, courseId)).isEqualTo(first);
        assertThatThrownBy(() -> courseRuns.prepare(owner, id, UUID.randomUUID()))
                .isInstanceOfSatisfying(AppException.class, e -> assertThat(e.getErrorCode()).isEqualTo(RunErrorCode.CONFLICT));
    }

    @Test
    void inactiveCourseCannotBePrepared() {
        when(courseApi.getRouteForRun(any())).thenThrow(new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE));

        assertThatThrownBy(() -> courseRuns.prepare(owner, id, courseId))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CourseErrorCode.COURSE_NOT_AVAILABLE));
    }

    @Test
    void startPublishesChallengeAndRunnerOnceEvenWhenRetried(AssertablePublishedEvents events) {
        startCourse();
        courseRuns.start(owner, id, startedAt); // 같은 startedAt 재시도

        List<CourseRunStartedEvent> started = all(events, CourseRunStartedEvent.class);
        assertThat(started).singleElement().satisfies(e -> {
            assertThat(e.courseId()).isEqualTo(courseId);
            assertThat(e.runSessionId()).isEqualTo(id);
            assertThat(e.memberId()).isEqualTo(owner);
        });
        assertThat(all(events, CourseActiveRunnersChangedEvent.class)).singleElement().satisfies(e -> {
            assertThat(e.activeCount()).isEqualTo(1);
            assertThat(e.version()).isEqualTo(1);
        });
        assertThatThrownBy(() -> courseRuns.start(owner, id, startedAt.plusSeconds(1)))
                .isInstanceOfSatisfying(AppException.class, e -> assertThat(e.getErrorCode()).isEqualTo(RunErrorCode.CONFLICT));
    }

    @Test
    void segmentEndReleasesOnceAndUnknownSessionIsIgnored(AssertablePublishedEvents events) {
        startCourse();
        courseRuns.segmentEnd(owner, id);
        courseRuns.segmentEnd(owner, id); // 이미 빠짐 → 무시
        courseRuns.segmentEnd(owner, UUID.randomUUID()); // 자유 러닝·모르는 세션 → 무시

        assertThat(all(events, CourseActiveRunnersChangedEvent.class))
                .extracting(CourseActiveRunnersChangedEvent::activeCount, CourseActiveRunnersChangedEvent::version)
                .containsExactly(org.assertj.core.groups.Tuple.tuple(1, 1L), org.assertj.core.groups.Tuple.tuple(0, 2L));
    }

    @Test
    void uploadReleasesWhenNoSegmentEndAndIsJudged(AssertablePublishedEvents events) {
        startCourse();
        uploadAndProcess(runTo(1000));

        // 구간 종료 신호가 없어 업로드 도착에서 −1
        assertThat(all(events, CourseActiveRunnersChangedEvent.class)).last()
                .satisfies(e -> assertThat(e.activeCount()).isZero());

        CourseOutcome course = runs.result(owner, id).course();
        assertThat(course.completed()).isTrue();
        assertThat(course.reason()).isEqualTo("COMPLETED");
        assertThat(course.recognizedDistanceMeters()).isCloseTo(1000, within(1.0));
        assertThat(course.reviewEligible()).isTrue();

        assertThat(all(events, RunSessionEndedEvent.class)).singleElement().satisfies(e -> {
            assertThat(e.courseId()).isEqualTo(courseId);
            assertThat(e.completed()).isTrue();
            assertThat(e.courseDistanceMeters()).isEqualTo(1000);
            assertThat(e.recognizedDistanceMeters()).isCloseTo(1000, within(1.0));
            assertThat(e.progress()).isCloseTo(100, within(0.1));
            assertThat(e.reviewEligible()).isTrue();
            assertThat(e.completedAt()).isNotNull();
            assertThat(e.courseElapsedSeconds()).isPositive();
        });
    }

    @Test
    void unfinishedCourseRunIsRegisteredAsNotCompleted(AssertablePublishedEvents events) {
        startCourse();
        uploadAndProcess(runTo(500));

        assertThat(all(events, RunSessionEndedEvent.class)).singleElement().satisfies(e -> {
            assertThat(e.courseId()).isEqualTo(courseId);
            assertThat(e.completed()).isFalse();
            assertThat(e.completedAt()).isNull();
            assertThat(e.progress()).isCloseTo(50, within(0.6));
            assertThat(e.reviewEligible()).isFalse(); // 500m < 1km
        });
        assertThat(runs.result(owner, id).course().reason()).isEqualTo("FINISH_NOT_REACHED");
    }

    @Test
    void deletingCourseRecordCarriesCourseValuesAndStartEventTime(AssertablePublishedEvents events) {
        startCourse();
        uploadAndProcess(runTo(1000));
        Instant startEventAt = all(events, CourseRunStartedEvent.class).getFirst().occurredAt();

        runs.delete(owner, id);

        assertThat(all(events, RunRecordDeletedEvent.class)).singleElement().satisfies(e -> {
            assertThat(e.courseId()).isEqualTo(courseId);
            assertThat(e.completed()).isTrue();
            assertThat(e.courseElapsedSeconds()).isPositive();
            assertThat(e.startedAt()).isEqualTo(startEventAt);
        });
        assertThat(db.queryForObject("SELECT count(*) FROM run.course_attempts", Long.class)).isZero();
    }

    @Test
    void recordListCarriesCourseSummaryAndFreeRunHasNone() {
        startCourse();
        uploadAndProcess(runTo(1000));
        UUID free = UUID.randomUUID();
        List<Input> inputs = runTo(300);
        runs.prepare(owner, free, new Prepare(startedAt, "FREE"));
        runs.upload(owner, free, new Upload(inputs.size() - 1, inputs));
        runs.process(free);

        assertThat(runs.result(owner, id).course().courseName()).isEqualTo("테스트 코스");
        List<RecordSummary> list = runs.history(owner, new Cursorable(null, 20)).content();
        assertThat(list).filteredOn(r -> r.id().equals(id)).singleElement().satisfies(r -> {
            assertThat(r.course().courseId()).isEqualTo(courseId);
            assertThat(r.course().courseName()).isEqualTo("테스트 코스");
            assertThat(r.course().completed()).isTrue();
            assertThat(r.course().progressPercent()).isCloseTo(100, within(0.1));
            assertThat(r.course().reviewEligible()).isTrue();
        });
        assertThat(list).filteredOn(r -> r.id().equals(free)).singleElement()
                .satisfies(r -> assertThat(r.course()).isNull());
    }

    @Test
    void migrationFillsCourseSummaryOfRecordsStoredBefore() throws IOException {
        startCourse();
        uploadAndProcess(runTo(500));
        // 이 변경 전 저장 모양: 목록에 course 없음, 상세 course에 이름 없음
        db.update("UPDATE run.records SET summary_json = (summary_json::jsonb - 'course')::text,"
                + " result_json = (result_json::jsonb #- '{course,courseName}')::text WHERE id = ?", id);
        assertThat(runs.history(owner, new Cursorable(null, 20)).content().getFirst().course()).isNull();

        db.execute(new ClassPathResource("db/migration/run/V20261021_2000__run_record_summary_course.sql")
                .getContentAsString(StandardCharsets.UTF_8));

        RecordSummary summary = runs.history(owner, new Cursorable(null, 20)).content().getFirst();
        assertThat(summary.course().courseName()).isEqualTo("테스트 코스");
        assertThat(summary.course().completed()).isFalse();
        assertThat(summary.course().progressPercent()).isCloseTo(50, within(0.6));
        assertThat(runs.result(owner, id).course().courseName()).isEqualTo("테스트 코스");
    }

    @Test
    void uploadPrepareFollowsStoredCourseAttempt() {
        courseRuns.prepare(owner, id, courseId);

        // 시작 신호 전
        assertThatThrownBy(() -> runs.prepare(owner, id, new Prepare(startedAt, "COURSE")))
                .isInstanceOfSatisfying(AppException.class, e -> assertThat(e.getErrorCode()).isEqualTo(RunErrorCode.CONFLICT));
        courseRuns.start(owner, id, startedAt);
        // 시작 신호와 다른 startedAt
        assertThatThrownBy(() -> runs.prepare(owner, id, new Prepare(startedAt.plusSeconds(1), "FREE")))
                .isInstanceOfSatisfying(AppException.class, e -> assertThat(e.getErrorCode()).isEqualTo(RunErrorCode.CONFLICT));
        // 코스 시도가 없는 세션을 코스로
        assertThatThrownBy(() -> runs.prepare(owner, UUID.randomUUID(), new Prepare(startedAt, "COURSE")))
                .isInstanceOfSatisfying(AppException.class, e -> assertThat(e.getErrorCode()).isEqualTo(RunErrorCode.NOT_FOUND));
        // 앱이 코스 정보를 잃고 FREE로 준비해도 서버의 코스 시도로 판정한다
        assertThat(runs.prepare(owner, id, new Prepare(startedAt, "FREE")).processing()).isEqualTo("PREPARED");
        assertThat(runs.prepare(owner, id, new Prepare(startedAt, "COURSE")).processing()).isEqualTo("PREPARED");
    }

    @Test
    void freePrepareOfCourseSessionIsStillJudgedAsCourse(AssertablePublishedEvents events) {
        startCourse();
        List<Input> inputs = runTo(1000);
        runs.prepare(owner, id, new Prepare(startedAt, "FREE"));
        runs.upload(owner, id, new Upload(inputs.size() - 1, inputs));
        runs.process(id);

        assertThat(runs.result(owner, id).course().completed()).isTrue();
        assertThat(all(events, RunSessionEndedEvent.class)).singleElement()
                .satisfies(e -> assertThat(e.courseId()).isEqualTo(courseId));
    }

    @Test
    void freeSessionCannotBecomeCourseRun() {
        runs.prepare(owner, id, new Prepare(startedAt, "FREE"));

        assertThatThrownBy(() -> courseRuns.prepare(owner, id, courseId))
                .isInstanceOfSatisfying(AppException.class, e -> assertThat(e.getErrorCode()).isEqualTo(RunErrorCode.CONFLICT));
    }

    @Test
    void runsWithoutSignalOrUploadAreReleasedAfterTimeout(AssertablePublishedEvents events) {
        startCourse();
        db.update("UPDATE run.course_attempts SET started_at = ? WHERE session_id = ?",
                Timestamp.from(Instant.now().minus(CourseRunService.ACTIVE_TIMEOUT).minus(Duration.ofMinutes(1))), id);

        assertThat(courseRuns.expiredIds()).containsExactly(id);
        courseRuns.releaseExpired(id);

        assertThat(all(events, CourseActiveRunnersChangedEvent.class)).last()
                .satisfies(e -> assertThat(e.activeCount()).isZero());
        assertThat(courseRuns.expiredIds()).isEmpty();
    }

    @Test
    void apiShape() throws Exception {
        mvc.perform(put("/api/v1/runs/sessions/" + id + "/course").with(jwt().jwt(j -> j.subject(owner.toString())))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"courseId\":\"" + courseId + "\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.courseId").value(courseId.toString()))
                .andExpect(jsonPath("$.data.totalDistanceMeters").value(1000))
                .andExpect(jsonPath("$.data.route.length()").value(2));
        mvc.perform(post("/api/v1/runs/sessions/" + id + "/course/start").with(jwt().jwt(j -> j.subject(owner.toString())))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"startedAt\":\"" + startedAt + "\"}"))
                .andExpect(status().isOk());
        mvc.perform(post("/api/v1/runs/sessions/" + id + "/course/segment-end").with(jwt().jwt(j -> j.subject(owner.toString()))))
                .andExpect(status().isOk());
    }
}
