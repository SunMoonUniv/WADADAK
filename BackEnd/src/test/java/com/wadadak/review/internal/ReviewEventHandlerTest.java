package com.wadadak.review.internal;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.course.CourseStatusReason;
import com.wadadak.event.run.RunRecordDeletedEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.verify;

/**
 * 이벤트는 커밋 뒤 다른 스레드에서 처리되므로, 아웃박스가 빌 때까지 기다린 다음 확인한다(ranking과 같은 방식).
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class ReviewEventHandlerTest {

    @Autowired
    TransactionTemplate transactionTemplate;

    @Autowired
    ApplicationEventPublisher publisher;

    @Autowired
    JdbcTemplate jdbc;

    /** 사진 파일 삭제는 흉내만 내고, 어떤 키를 지우라고 했는지만 본다 */
    @MockitoBean
    ObjectStorage storage;

    // review만 띄워서 member 모듈이 없다. 리뷰 조회 서비스가 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Test
    void hiddenCourseKeepsReviewsAndDeletedCourseDropsThem() {
        UUID course = UUID.randomUUID();
        UUID review = review(course);
        String photo = photo(review);
        runRecord(course);
        UUID otherCourse = UUID.randomUUID();
        String otherPhoto = photo(review(otherCourse));
        runRecord(otherCourse);

        publish(courseStatus(course, CourseStatus.HIDDEN, 1));
        assertThat(courseStatus(course)).isEqualTo("HIDDEN");
        assertThat(count("review.reviews", course)).isOne(); // 숨김은 지우지 않는다. 조회·작성에서만 막는다

        publish(courseStatus(course, CourseStatus.DELETED, 3));
        publish(courseStatus(course, CourseStatus.HIDDEN, 2));  // 늦게 온 옛 버전
        publish(courseStatus(course, CourseStatus.DELETED, 3)); // 중복

        assertThat(courseStatus(course)).isEqualTo("DELETED");
        assertThat(count("review.reviews", course)).isZero();
        assertThat(count("review.course_run_records", course)).isZero();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM review.review_photos WHERE review_id = ?", Long.class, review))
                .isZero();
        // 다른 코스는 그대로
        assertThat(count("review.reviews", otherCourse)).isOne();
        assertThat(count("review.course_run_records", otherCourse)).isOne();
        // 지운 코스의 사진 파일만 지우라고 했다
        @SuppressWarnings("unchecked")
        ArgumentCaptor<Collection<String>> deleted = ArgumentCaptor.forClass(Collection.class);
        verify(storage, atLeastOnce()).deleteAfterCommit(deleted.capture());
        assertThat(deleted.getAllValues().stream().flatMap(Collection::stream)).containsExactly(photo).doesNotContain(otherPhoto);
    }

    @Test
    void copiesCourseRunRecordOnce() {
        UUID course = UUID.randomUUID();
        UUID member = UUID.randomUUID();
        RunSessionEndedEvent ended = ended(UUID.randomUUID(), member, course, 62.7, true);

        publish(ended);
        publish(ended); // 중복

        Map<String, Object> row = jdbc.queryForMap("SELECT * FROM review.course_run_records WHERE run_record_id = ?",
                ended.runRecordId());
        assertThat(row.get("member_id")).isEqualTo(member);
        assertThat(row.get("course_id")).isEqualTo(course);
        assertThat(row.get("review_eligible")).isEqualTo(true);
        assertThat(row.get("progress_percent")).isEqualTo(62); // 내림
        assertThat(row.get("course_distance_meters")).isEqualTo(5200);
        assertThat(row.get("course_elapsed_seconds")).isEqualTo(1634);
        assertThat(row.get("deleted")).isEqualTo(false);
    }

    @Test
    void ignoresFreeRunHiddenCourseAndWithdrawnMember() {
        UUID hiddenCourse = UUID.randomUUID();
        publish(courseStatus(hiddenCourse, CourseStatus.HIDDEN, 1));
        UUID withdrawn = UUID.randomUUID();
        jdbc.update("INSERT INTO review.withdrawn_members VALUES (?, now(), now(), now())", withdrawn);

        UUID freeRun = UUID.randomUUID();
        UUID onHidden = UUID.randomUUID();
        UUID ofWithdrawn = UUID.randomUUID();
        publish(ended(freeRun, UUID.randomUUID(), null, 0, false));
        publish(ended(onHidden, UUID.randomUUID(), hiddenCourse, 100, true));
        publish(ended(ofWithdrawn, withdrawn, UUID.randomUUID(), 100, true));

        for (UUID record : new UUID[]{freeRun, onHidden, ofWithdrawn}) {
            assertThat(recordCount(record)).isZero();
        }
    }

    @Test
    void deletionMarksRecordEvenWhenItArrivesFirst() {
        UUID course = UUID.randomUUID();
        UUID member = UUID.randomUUID();
        RunSessionEndedEvent normal = ended(UUID.randomUUID(), member, course, 100, true);
        RunSessionEndedEvent late = ended(UUID.randomUUID(), member, course, 80, true);

        publish(normal);
        publish(deleted(normal));
        // 삭제가 먼저 처리되고 주행 기록이 늦게 와도 되살아나지 않는다
        publish(deleted(late));
        publish(late);

        assertThat(jdbc.queryForObject("SELECT deleted FROM review.course_run_records WHERE run_record_id = ?",
                Boolean.class, normal.runRecordId())).isTrue();
        Map<String, Object> lateRow = jdbc.queryForMap("SELECT * FROM review.course_run_records WHERE run_record_id = ?",
                late.runRecordId());
        assertThat(lateRow.get("deleted")).isEqualTo(true);
        assertThat(lateRow.get("progress_percent")).isEqualTo(80); // 늦게 온 값은 채운다
    }

    @Test
    void newRunDoesNotRaiseProgressOfWrittenReview() {
        UUID course = UUID.randomUUID();
        UUID member = UUID.randomUUID();
        UUID review = review(course);
        jdbc.update("UPDATE review.reviews SET member_id = ?, best_progress_percent = 40 WHERE id = ?", member, review);

        publish(ended(UUID.randomUUID(), member, course, 100, true));

        // 리뷰의 최고 진행도는 리뷰를 수정할 때 올린다(D-09)
        assertThat(jdbc.queryForObject("SELECT best_progress_percent FROM review.reviews WHERE id = ?", Integer.class, review))
                .isEqualTo(40);
    }

    /** 5.2km 코스를 27분 14초에 달린 기록. 진행도 100이면 완주다. 자유 러닝은 courseId가 null이다. */
    private static RunSessionEndedEvent ended(UUID runRecordId, UUID memberId, UUID courseId, double progress, boolean eligible) {
        Instant endedAt = Instant.parse("2026-10-15T01:00:00Z");
        boolean completed = progress >= 100;
        return new RunSessionEndedEvent(UUID.randomUUID(), endedAt, runRecordId, memberId, courseId, completed,
                5200, 1634, 5200, 5200 * progress / 100, progress, eligible, completed ? endedAt : null,
                endedAt.minusSeconds(1634), endedAt, endedAt, "test");
    }

    private static RunRecordDeletedEvent deleted(RunSessionEndedEvent ended) {
        return new RunRecordDeletedEvent(UUID.randomUUID(), Instant.now(), ended.runRecordId(), ended.memberId(),
                ended.courseId(), ended.completed(), ended.distanceMeters(), ended.courseElapsedSeconds(),
                ended.startedAt(), ended.endedAt(), ended.registeredAt());
    }

    private long recordCount(UUID runRecordId) {
        return jdbc.queryForObject("SELECT count(*) FROM review.course_run_records WHERE run_record_id = ?", Long.class, runRecordId);
    }

    private void publish(Object event) {
        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(jdbc.queryForObject("SELECT count(*) FROM common.event_publication", Long.class)).isZero());
    }

    private static CourseStatusChangedEvent courseStatus(UUID courseId, CourseStatus status, long version) {
        return new CourseStatusChangedEvent(UUID.randomUUID(), Instant.now(), courseId, status,
                CourseStatusReason.USER_DELETED, version);
    }

    private String courseStatus(UUID courseId) {
        return jdbc.queryForObject("SELECT status FROM review.course_status_copies WHERE course_id = ?", String.class, courseId);
    }

    private long count(String table, UUID courseId) {
        return jdbc.queryForObject("SELECT count(*) FROM " + table + " WHERE course_id = ?", Long.class, courseId);
    }

    private UUID review(UUID courseId) {
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO review.reviews (id, course_id, member_id, source_run_record_id, rating, safety_rating,
                    road_rating, lighting_rating, amenity_rating, best_progress_percent, created_at, updated_at)
                VALUES (?, ?, ?, ?, 5, 5, 5, 5, 5, 100, now(), now())""", id, courseId, UUID.randomUUID(), UUID.randomUUID());
        return id;
    }

    private String photo(UUID reviewId) {
        String key = "review/" + UUID.randomUUID() + ".jpg";
        jdbc.update("""
                INSERT INTO review.review_photos (id, review_id, photo_key, display_order, created_at, updated_at)
                VALUES (?, ?, ?, 0, now(), now())""", UUID.randomUUID(), reviewId, key);
        return key;
    }

    private void runRecord(UUID courseId) {
        jdbc.update("""
                INSERT INTO review.course_run_records (run_record_id, course_id, member_id, review_eligible, completed,
                    progress_percent, course_distance_meters, course_elapsed_seconds, ended_at, created_at, updated_at)
                VALUES (?, ?, ?, TRUE, TRUE, 100, 5200, 1634, now(), now(), now())""",
                UUID.randomUUID(), courseId, UUID.randomUUID());
    }
}
