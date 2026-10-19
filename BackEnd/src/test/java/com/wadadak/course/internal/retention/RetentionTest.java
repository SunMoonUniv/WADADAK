package com.wadadak.course.internal.retention;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.event.course.CourseExpiringSoonEvent;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.course.CourseStatusReason;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.modulith.test.AssertablePublishedEvents;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.convention.TestBean;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

/**
 * 완주 연장(이벤트 수신)과 만료 배치. 배치는 테스트에서 꺼 두고({@code app.course.retention-batch.enabled}) 직접 부른다.
 * 시각은 Asia/Seoul = UTC+9로 적는다.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RetentionTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    /** 배치가 보는 지금. 테스트마다 맞춘다 */
    @TestBean
    Clock clock;

    static final MovableClock CLOCK = new MovableClock();

    static Clock clock() {
        return CLOCK;
    }

    @Autowired
    CourseRepository courseRepository;

    @Autowired
    RetentionService retention;

    @Autowired
    TransactionTemplate transactionTemplate;

    @Autowired
    ApplicationEventPublisher publisher;

    @Autowired
    JdbcTemplate jdbc;

    RetentionScheduler scheduler;

    @BeforeEach
    void setUp() {
        scheduler = new RetentionScheduler(courseRepository, retention, clock);
    }

    @Test
    void completionExtendsOncePerFixedPeriod() {
        UUID course = save(seoul("2026-10-30T23:59:59"));
        RunSessionEndedEvent first = ended(course, true, seoul("2026-10-05T08:00:00"));

        receive(first);
        assertThat(expiresAt(course)).isEqualTo(seoul("2026-11-29T23:59:59"));
        receive(first); // 같은 이벤트를 다시 받아도 결과가 같다(개발 정책 10.6)
        assertThat(expiresAt(course)).isEqualTo(seoul("2026-11-29T23:59:59"));

        receive(ended(course, true, seoul("2026-10-10T08:00:00"))); // 같은 구간의 다른 완주
        receive(ended(null, true, seoul("2026-10-31T08:00:00")));   // 자유 러닝
        receive(ended(course, false, seoul("2026-10-31T08:00:00"))); // 미완주
        assertThat(expiresAt(course)).isEqualTo(seoul("2026-11-29T23:59:59"));

        receive(ended(course, true, seoul("2026-10-31T08:00:00")));
        assertThat(expiresAt(course)).isEqualTo(seoul("2026-12-29T23:59:59"));
    }

    @Test
    void completionAfterExpiryOrOnHiddenCourseDoesNotExtend() {
        UUID late = save(seoul("2026-10-30T23:59:59"));
        UUID hidden = save(seoul("2026-10-30T23:59:59"));
        jdbc.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'USER_DELETED', hidden_at = now() WHERE id = ?",
                hidden);

        receive(ended(late, true, seoul("2026-10-31T00:00:00")));
        receive(ended(hidden, true, seoul("2026-10-20T08:00:00")));

        assertThat(expiresAt(late)).isEqualTo(seoul("2026-10-30T23:59:59"));
        assertThat(expiresAt(hidden)).isEqualTo(seoul("2026-10-30T23:59:59"));
        assertThat(status(hidden)).isEqualTo("HIDDEN");
    }

    @Test
    void completionReceivedAfterExpiryDoesNotExtendBeforeBatchRuns() {
        UUID course = save(seoul("2026-10-30T23:59:59"));

        // 만료 10초 전에 등록된 완주를 만료 10초 뒤에 받았다. 배치가 아직 돌지 않아 공개 중이다(정책 공통 4)
        receive(ended(course, true, seoul("2026-10-30T23:59:50")), seoul("2026-10-31T00:00:10"));
        assertThat(status(course)).isEqualTo("ACTIVE");
        assertThat(expiresAt(course)).isEqualTo(seoul("2026-10-30T23:59:59"));

        scheduler.hideAndDelete();
        assertThat(status(course)).isEqualTo("HIDDEN");
    }

    @Test
    void hidesExpiredCourseAndDeletesItADayLater(AssertablePublishedEvents events) {
        UUID expired = save(seoul("2026-10-30T23:59:59"));
        UUID lastDay = save(seoul("2026-10-31T23:59:59"));

        CLOCK.set(seoul("2026-10-31T00:00:30"));
        scheduler.hideAndDelete();

        assertThat(status(expired)).isEqualTo("HIDDEN");
        assertThat(status(lastDay)).as("만료일 당일은 공개").isEqualTo("ACTIVE");
        assertThat(jdbc.queryForMap("SELECT status_reason, hidden_at FROM course.courses WHERE id = ?", expired))
                .containsEntry("status_reason", "EXPIRED");
        long hiddenVersion = version(expired);
        assertThat(hiddenVersion).isPositive();
        assertThat(events).contains(CourseStatusChangedEvent.class)
                .matching(e -> e.courseId().equals(expired) && e.status() == CourseStatus.HIDDEN
                        && e.reason() == CourseStatusReason.EXPIRED && e.version() == hiddenVersion);

        // 숨기기 전에 쌓인 통계. 숨겨도 남고, 삭제하면 지운다(개발 정책 6.2)
        jdbc.update("INSERT INTO course.course_stats (course_id, review_count, rating_sum, created_at, updated_at) "
                + "VALUES (?, 1, 5, now(), now())", expired);
        jdbc.update("INSERT INTO course.course_daily_stats (id, course_id, stat_date, view_count, created_at, updated_at) "
                + "VALUES (?, ?, DATE '2026-10-20', 3, now(), now())", UUID.randomUUID(), expired);

        CLOCK.set(seoul("2026-11-01T00:00:29"));
        scheduler.hideAndDelete();
        assertThat(status(expired)).as("24시간이 안 됐다").isEqualTo("HIDDEN");
        assertThat(statsRows(expired)).isEqualTo(2);

        CLOCK.set(seoul("2026-11-01T00:00:30"));
        scheduler.hideAndDelete();
        assertThat(status(expired)).isEqualTo("DELETED");
        assertThat(statsRows(expired)).as("삭제하면 통계도 지운다").isZero();
        assertThat(status(lastDay)).isEqualTo("HIDDEN");
        long deletedVersion = version(expired);
        assertThat(deletedVersion).as("상태가 바뀔 때마다 버전이 커진다").isGreaterThan(hiddenVersion);
        assertThat(events).contains(CourseStatusChangedEvent.class)
                .matching(e -> e.courseId().equals(expired) && e.status() == CourseStatus.DELETED
                        && e.reason() == CourseStatusReason.EXPIRED && e.version() == deletedVersion);
    }

    @Test
    void extendedCourseIsNotHidden() {
        UUID course = save(seoul("2026-10-30T23:59:59"));
        // 만료 직전 완주가 배치보다 먼저 처리됐다
        receive(ended(course, true, seoul("2026-10-30T23:50:00")));

        CLOCK.set(seoul("2026-10-31T00:00:30"));
        scheduler.hideAndDelete();

        assertThat(status(course)).isEqualTo("ACTIVE");
        assertThat(retention.hideIfExpired(course)).isFalse();
    }

    @Test
    void noticesCoursesSevenDaysAndOneDayBeforeExpiry(AssertablePublishedEvents events) {
        UUID creator = UUID.randomUUID();
        UUID sevenDays = save(seoul("2027-01-08T23:59:59"), creator, "일주일 남은 코스");
        UUID oneDay = save(seoul("2027-01-02T23:59:59"), creator, "하루 남은 코스");
        UUID fourDays = save(seoul("2027-01-05T23:59:59"), creator, "나흘 남은 코스");
        UUID hidden = save(seoul("2027-01-08T23:59:59"), creator, "숨긴 코스");
        jdbc.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'USER_DELETED', hidden_at = now() WHERE id = ?",
                hidden);

        CLOCK.set(seoul("2027-01-01T09:00:00"));
        scheduler.noticeExpiringSoon();

        assertThat(events).contains(CourseExpiringSoonEvent.class)
                .matching(e -> e.courseId().equals(sevenDays) && e.daysLeft() == 7 && e.creatorId().equals(creator)
                        && e.courseName().equals("일주일 남은 코스") && e.expiresAt().equals(seoul("2027-01-08T23:59:59")));
        assertThat(events).contains(CourseExpiringSoonEvent.class)
                .matching(e -> e.courseId().equals(oneDay) && e.daysLeft() == 1);
        assertThat(events.ofType(CourseExpiringSoonEvent.class)).extracting(CourseExpiringSoonEvent::courseId)
                .doesNotContain(fourDays, hidden);
    }

    private UUID save(Instant expiresAt) {
        return save(expiresAt, UUID.randomUUID(), "유지 기간 코스 " + UUID.randomUUID());
    }

    private UUID save(Instant expiresAt, UUID creator, String name) {
        // 이름이 공개 코스 사이에서 유일해야 한다. 경로 · 거리는 유지 기간과 관계없다
        return courseRepository.saveAndFlush(Course.registerCustom(creator, name, Difficulty.MEDIUM, Set.of(),
                CourseGeometry.lineString(List.of(new GeoPoint(37.5000, 127.1000), new GeoPoint(37.5090, 127.1000))),
                1000, "1171010100", expiresAt)).getId();
    }

    /** 기록이 등록되고 30초 뒤에 받는다 */
    private void receive(RunSessionEndedEvent event) {
        receive(event, event.registeredAt().plusSeconds(30));
    }

    private void receive(RunSessionEndedEvent event, Instant receivedAt) {
        CLOCK.set(receivedAt);
        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(jdbc.queryForObject("SELECT count(*) FROM common.event_publication", Long.class)).isZero());
    }

    private static RunSessionEndedEvent ended(UUID courseId, boolean completed, Instant registeredAt) {
        return new RunSessionEndedEvent(UUID.randomUUID(), registeredAt, UUID.randomUUID(), UUID.randomUUID(), courseId,
                completed, 1000, 300, 1000, 1000, 1, true, completed ? registeredAt : null, registeredAt.minusSeconds(600),
                registeredAt.minusSeconds(60), registeredAt, "2026-10-14");
    }

    private Instant expiresAt(UUID courseId) {
        return jdbc.queryForObject("SELECT expires_at FROM course.courses WHERE id = ?", java.sql.Timestamp.class, courseId)
                .toInstant();
    }

    private String status(UUID courseId) {
        return jdbc.queryForObject("SELECT status FROM course.courses WHERE id = ?", String.class, courseId);
    }

    private long statsRows(UUID courseId) {
        return jdbc.queryForObject("SELECT (SELECT count(*) FROM course.course_stats WHERE course_id = ?) "
                + "+ (SELECT count(*) FROM course.course_daily_stats WHERE course_id = ?)", Long.class, courseId, courseId);
    }

    private long version(UUID courseId) {
        return jdbc.queryForObject("SELECT version FROM course.courses WHERE id = ?", Long.class, courseId);
    }

    /** Asia/Seoul 시각 */
    private static Instant seoul(String localDateTime) {
        return Instant.parse(localDateTime + "+09:00");
    }

    /** 테스트가 옮기는 시계 */
    static final class MovableClock extends Clock {

        private volatile Instant now = Instant.parse("2026-10-01T01:00:00Z");

        void set(Instant now) {
            this.now = now;
        }

        @Override
        public ZoneId getZone() {
            return ZoneId.of("Asia/Seoul");
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return Clock.fixed(now, zone);
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}
