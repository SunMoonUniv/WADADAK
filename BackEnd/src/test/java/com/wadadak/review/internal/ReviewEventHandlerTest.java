package com.wadadak.review.internal;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.course.CourseStatusReason;
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
