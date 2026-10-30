package com.wadadak.course.internal.stats;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.event.review.ReviewCreatedEvent;
import com.wadadak.event.review.ReviewDeletedEvent;
import com.wadadak.event.review.ReviewUpdatedEvent;
import com.wadadak.event.run.CourseActiveRunnersChangedEvent;
import com.wadadak.event.run.CourseRunStartedEvent;
import com.wadadak.event.run.RunRecordDeletedEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.support.TransactionTemplate;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.entry;
import static org.awaitility.Awaitility.await;

/**
 * 코스 러닝 시작 · 완주 · 기록 삭제 · 리뷰 이벤트로 코스 통계가 늘고 줄고, 현재 러너 수 이벤트로 복사본이 바뀐다(개발 정책 5.4 · 5.6).
 * 시각은 Asia/Seoul = UTC+9로 적는다.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseStatsTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    CourseStatsService courseStats;

    @Autowired
    TransactionTemplate transactionTemplate;

    @Autowired
    ApplicationEventPublisher publisher;

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void completionsAddUpOnceEachAndRecordDeletionTakesThemBack() {
        UUID course = insert("ACTIVE", 5_000);
        RunSessionEndedEvent first = ended(course, true, 1_800);
        UUID secondRecord = UUID.randomUUID();

        receive(first);
        receive(first); // 같은 이벤트를 다시 받아도 한 번만 센다(개발 정책 5.4)
        receive(ended(secondRecord, course, true, 2_100));
        receive(ended(null, true, 600));      // 자유 러닝
        receive(ended(course, false, 3_000)); // 미완주

        assertThat(stats(course)).containsEntry("completion_count", 2).containsEntry("completion_seconds", 3_900L);
        // (30분 + 35분) ÷ 2 ÷ 5km = 390초/km
        assertThat(courseStats.averagePaceSecondsPerKm(course, 5_000)).isEqualTo(390);

        RunRecordDeletedEvent deleted = deleted(secondRecord, course, true, 2_100);
        receive(deleted);
        receive(deleted);
        receive(deleted(UUID.randomUUID(), course, false, 3_000)); // 미완주 기록 삭제는 완주 수와 관계없다

        assertThat(stats(course)).containsEntry("completion_count", 1).containsEntry("completion_seconds", 1_800L);
        assertThat(courseStats.averagePaceSecondsPerKm(course, 5_000)).isEqualTo(360);
    }

    /** 완주 한 건마다 한 줄(G4 최근 주행). 지운 기록은 지운 표시만 남고, 코스가 삭제되면 줄을 모두 지운다 */
    @Test
    void completionRowsFollowCompletionsAndRecordDeletion() {
        UUID course = insert("ACTIVE", 5_000);
        RunSessionEndedEvent kept = completedAt(course, seoul("2026-10-20T08:00:00"));
        RunSessionEndedEvent removed = completedAt(course, seoul("2026-10-25T08:00:00"));

        receive(kept);
        receive(kept);
        receive(removed);
        receive(deleted(removed.runRecordId(), course, true, 1_800));
        receive(ended(course, false, 3_000)); // 미완주는 줄이 없다

        assertThat(completionRows(course)).containsOnly(entry(kept.runRecordId(), false), entry(removed.runRecordId(), true));
        assertThat(lastCompletedAt(course)).isEqualTo(seoul("2026-10-20T08:00:00"));

        courseStats.deleteFor(course);
        assertThat(completionRows(course)).isEmpty();
    }

    /** 기록 삭제를 완주보다 먼저 받아도 그 완주는 최근 주행에 들어가지 않는다(개발 정책 5.4) */
    @Test
    void completionDeletedBeforeItArrivesStaysOut() {
        UUID course = insert("ACTIVE", 5_000);
        RunSessionEndedEvent late = completedAt(course, seoul("2026-10-20T08:00:00"));

        receive(deleted(late.runRecordId(), course, true, 1_800));
        receive(late);

        assertThat(stats(course)).containsEntry("completion_count", 0);
        assertThat(completionRows(course)).containsOnly(entry(late.runRecordId(), true));
        assertThat(lastCompletedAt(course)).isNull();
    }

    @Test
    void challengesCountEachStartOnceAndRecordDeletionTakesThemBackOnTheStartDay() {
        UUID course = insert("ACTIVE", 3_000);
        Instant lateNight = seoul("2026-10-10T23:50:00"); // 서울 10/10, UTC로는 10/10 14:50
        CourseRunStartedEvent first = started(course, lateNight);

        receive(first);
        receive(first); // 같은 시작을 다시 받아도 한 번만 센다(개발 정책 5.4)
        receive(started(course, seoul("2026-10-11T00:10:00")));
        receive(started(course, seoul("2026-10-11T07:00:00")));
        assertThat(stats(course)).containsEntry("challenge_count", 3);
        assertThat(daily(course, LocalDate.of(2026, 10, 10))).containsEntry("challenge_count", 1);
        assertThat(daily(course, LocalDate.of(2026, 10, 11))).containsEntry("challenge_count", 2);

        // 다음 날 지워도 시작한 날(10/10)에서 뺀다. 완주와 상관없이 코스 기록이면 뺀다(개발 정책 5.6)
        RunRecordDeletedEvent deleted = deleted(UUID.randomUUID(), course, false, 1_200, lateNight, seoul("2026-10-12T09:00:00"));
        receive(deleted);
        receive(deleted);
        receive(deleted(UUID.randomUUID(), course, true, 1_500, seoul("2026-10-11T07:00:00"), seoul("2026-10-12T09:00:00")));
        receive(deleted(UUID.randomUUID(), null, false, 1_000, lateNight, seoul("2026-10-12T09:00:00"))); // 자유 러닝

        assertThat(stats(course)).containsEntry("challenge_count", 1);
        assertThat(daily(course, LocalDate.of(2026, 10, 10))).containsEntry("challenge_count", 0);
        assertThat(daily(course, LocalDate.of(2026, 10, 11))).containsEntry("challenge_count", 1);
        assertThat(daily(course, LocalDate.of(2026, 10, 12))).as("지운 날 행은 없다").isEmpty();
    }

    /** 현재 러너 수는 더 큰 version만 남는다. 늦게 온 예전 값 · 같은 version은 버린다(개발 정책 5.4 상태 복사형) */
    @Test
    void activeRunnersKeepTheNewestVersion() {
        UUID course = insert("ACTIVE", 3_000);
        assertThat(courseStats.activeRunners(course)).as("받은 적이 없으면 0명").isZero();

        receive(runners(course, 3, 2));
        receive(runners(course, 5, 1));
        receive(runners(course, 9, 2));
        assertThat(courseStats.activeRunners(course)).isEqualTo(3);

        receive(runners(course, 0, 3));
        assertThat(courseStats.activeRunners(course)).isZero();

        receive(runners(course, -1, 4));
        assertThat(courseStats.activeRunners(course)).as("0보다 작은 값은 0").isZero();
    }

    @Test
    void reviewsChangeTheTotalsAndTheirWritingDay() {
        UUID course = insert("ACTIVE", 3_000);
        UUID review = UUID.randomUUID();
        Instant writtenAt = seoul("2026-10-10T23:30:00"); // 서울 10/10, UTC로는 10/10 14:30
        ReviewCreatedEvent created = new ReviewCreatedEvent(UUID.randomUUID(), writtenAt, review, course, 5, writtenAt);

        receive(created);
        receive(created);
        receive(new ReviewCreatedEvent(UUID.randomUUID(), seoul("2026-10-11T08:00:00"), UUID.randomUUID(), course, 4,
                seoul("2026-10-11T08:00:00")));
        assertThat(stats(course)).containsEntry("rating_sum", 9).containsEntry("review_count", 2);

        // 다음 날 고쳐도 작성일(10/10) 행에 반영한다(개발 정책 5.6)
        ReviewUpdatedEvent updated = new ReviewUpdatedEvent(UUID.randomUUID(), seoul("2026-10-12T09:00:00"), review, course,
                5, 2, writtenAt);
        receive(updated);
        receive(updated);
        receive(new ReviewUpdatedEvent(UUID.randomUUID(), seoul("2026-10-12T09:10:00"), review, course, 2, 2, writtenAt));
        assertThat(stats(course)).containsEntry("rating_sum", 6).containsEntry("review_count", 2);
        assertThat(daily(course, LocalDate.of(2026, 10, 10))).containsEntry("rating_sum", 2).containsEntry("review_count", 1);
        assertThat(daily(course, LocalDate.of(2026, 10, 11))).containsEntry("rating_sum", 4).containsEntry("review_count", 1);
        assertThat(daily(course, LocalDate.of(2026, 10, 12))).as("고친 날 행은 없다").isEmpty();

        receive(new ReviewDeletedEvent(UUID.randomUUID(), seoul("2026-10-13T09:00:00"), review, course, 2, writtenAt));
        assertThat(stats(course)).containsEntry("rating_sum", 4).containsEntry("review_count", 1);
        assertThat(daily(course, LocalDate.of(2026, 10, 10))).containsEntry("rating_sum", 0).containsEntry("review_count", 0);
    }

    @Test
    void deletionArrivingFirstStillNetsOut() {
        UUID course = insert("ACTIVE", 3_000);
        UUID review = UUID.randomUUID();
        Instant writtenAt = seoul("2026-10-10T10:00:00");

        receive(new ReviewDeletedEvent(UUID.randomUUID(), writtenAt.plusSeconds(60), review, course, 3, writtenAt));
        receive(new ReviewCreatedEvent(UUID.randomUUID(), writtenAt, review, course, 3, writtenAt));

        assertThat(stats(course)).containsEntry("rating_sum", 0).containsEntry("review_count", 0);
    }

    /** 비공개 · 삭제된 코스는 통계를 바꾸지 않는다(정책 D-15) */
    @Test
    void ignoresHiddenCourses() {
        UUID hidden = insert("HIDDEN", 3_000);

        receive(ended(hidden, true, 1_000));
        receive(started(hidden, Instant.now()));
        receive(runners(hidden, 2, 1));
        receive(new ReviewCreatedEvent(UUID.randomUUID(), Instant.now(), UUID.randomUUID(), hidden, 5, Instant.now()));
        courseStats.recordView(hidden);

        assertThat(jdbc.queryForObject("SELECT count(*) FROM course.course_stats WHERE course_id = ?", Long.class, hidden))
                .isZero();
        assertThat(courseStats.averagePaceSecondsPerKm(hidden, 3_000)).isNull();
        assertThat(courseStats.activeRunners(hidden)).isZero();
        assertThat(completionRows(hidden)).isEmpty();
    }

    private void receive(Object event) {
        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(jdbc.queryForObject("SELECT count(*) FROM common.event_publication", Long.class)).isZero());
    }

    private static RunSessionEndedEvent ended(UUID courseId, boolean completed, int elapsedSeconds) {
        return ended(UUID.randomUUID(), courseId, completed, elapsedSeconds);
    }

    private static RunSessionEndedEvent ended(UUID recordId, UUID courseId, boolean completed, int elapsedSeconds) {
        Instant registeredAt = Instant.now();
        return new RunSessionEndedEvent(UUID.randomUUID(), registeredAt, recordId, UUID.randomUUID(), courseId, completed,
                5_000, elapsedSeconds, 5_000, 5_000, 1, completed, completed ? registeredAt : null,
                registeredAt.minusSeconds(elapsedSeconds), registeredAt, registeredAt, "2026-10-14");
    }

    /** [completedAt]에 30분 걸려 완주한 기록 */
    private static RunSessionEndedEvent completedAt(UUID courseId, Instant completedAt) {
        return new RunSessionEndedEvent(UUID.randomUUID(), completedAt, UUID.randomUUID(), UUID.randomUUID(), courseId, true,
                5_000, 1_800, 5_000, 5_000, 1, true, completedAt, completedAt.minusSeconds(1_800), completedAt, completedAt,
                "2026-10-14");
    }

    private static RunRecordDeletedEvent deleted(UUID recordId, UUID courseId, boolean completed, int elapsedSeconds) {
        Instant now = Instant.now();
        return deleted(recordId, courseId, completed, elapsedSeconds, now.minusSeconds(elapsedSeconds), now);
    }

    /** @param startedAt 도전 수를 더한 코스 러닝 시작 시각 */
    private static RunRecordDeletedEvent deleted(UUID recordId, UUID courseId, boolean completed, int elapsedSeconds,
                                                 Instant startedAt, Instant deletedAt) {
        Instant endedAt = startedAt.plusSeconds(elapsedSeconds);
        return new RunRecordDeletedEvent(UUID.randomUUID(), deletedAt, recordId, UUID.randomUUID(), courseId, completed, 5_000,
                elapsedSeconds, startedAt, endedAt, endedAt);
    }

    private static CourseRunStartedEvent started(UUID courseId, Instant startedAt) {
        return new CourseRunStartedEvent(UUID.randomUUID(), startedAt, UUID.randomUUID(), courseId, UUID.randomUUID());
    }

    private static CourseActiveRunnersChangedEvent runners(UUID courseId, int count, long version) {
        return new CourseActiveRunnersChangedEvent(UUID.randomUUID(), Instant.now(), courseId, count, version);
    }

    private Map<String, Object> stats(UUID course) {
        return jdbc.queryForMap("SELECT * FROM course.course_stats WHERE course_id = ?", course);
    }

    /** 완주 줄: 기록 ID → 지웠는지 */
    private Map<UUID, Boolean> completionRows(UUID course) {
        Map<UUID, Boolean> rows = new HashMap<>();
        jdbc.query("SELECT run_record_id, deleted_at IS NOT NULL AS deleted FROM course.course_completions WHERE course_id = ?",
                (RowCallbackHandler) rs -> rows.put(rs.getObject("run_record_id", UUID.class), rs.getBoolean("deleted")), course);
        return rows;
    }

    /** 지우지 않은 완주 중 마지막 완주 시각 */
    private Instant lastCompletedAt(UUID course) {
        Timestamp at = jdbc.queryForObject(
                "SELECT max(completed_at) FROM course.course_completions WHERE course_id = ? AND deleted_at IS NULL", Timestamp.class, course);
        return at == null ? null : at.toInstant();
    }

    private Map<String, Object> daily(UUID course, LocalDate day) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT * FROM course.course_daily_stats WHERE course_id = ? AND stat_date = ?", course, day);
        return rows.isEmpty() ? Map.of() : rows.getFirst();
    }

    /** 경로 · 지역은 통계와 관계없다. 만료는 넉넉히 뒤로 둔다 */
    private UUID insert(String status, int distanceMeters) {
        UUID id = UUID.randomUUID();
        boolean active = status.equals("ACTIVE");
        jdbc.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    status_reason, hidden_at, expires_at, version, created_at, updated_at)
                        VALUES (?, ?, 'CUSTOM', ?, ?, 'EASY', '{}'::varchar[],
                                ST_GeomFromText('LINESTRING(127.30 37.30, 127.30 37.31)', 4326), ?,
                                ST_GeogFromText('SRID=4326;POINT(127.30 37.30)'), '1171010100', '1171000000', '1100000000',
                                ?, ?, ?, ?, 0, now(), now())""",
                id, UUID.randomUUID(), "통계 코스 " + id, "통계코스" + id, distanceMeters, status, active ? null : "EXPIRED",
                active ? null : Timestamp.from(Instant.now()), Timestamp.from(Instant.now().plus(Duration.ofDays(30))));
        return id;
    }

    private static Instant seoul(String localDateTime) {
        return Instant.parse(localDateTime + "+09:00");
    }
}
