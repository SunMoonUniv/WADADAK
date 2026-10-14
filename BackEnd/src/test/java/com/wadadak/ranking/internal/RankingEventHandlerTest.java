package com.wadadak.ranking.internal;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.course.CourseStatusReason;
import com.wadadak.event.member.MemberVisibilityChangedEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.event.run.RunRecordDeletedEvent;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

/** 이벤트는 커밋 후 비동기로 처리되므로 아웃박스가 빌 때까지 기다린 뒤 확인한다. */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RankingEventHandlerTest {

    @Autowired
    TransactionTemplate transactionTemplate;

    @Autowired
    ApplicationEventPublisher publisher;

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void keepsNewestCourseStatusAndDropsEntriesOfDeletedCourse() {
        UUID course = UUID.randomUUID();
        insertEntry(course);

        publish(courseStatus(course, CourseStatus.HIDDEN, 1));
        assertThat(courseStatus(course)).isEqualTo("HIDDEN");
        assertThat(entryCount(course)).isOne();   // 숨김은 기록을 지우지 않는다

        publish(courseStatus(course, CourseStatus.DELETED, 3));
        publish(courseStatus(course, CourseStatus.HIDDEN, 2));    // 늦게 온 옛 버전
        publish(courseStatus(course, CourseStatus.DELETED, 3));   // 중복
        assertThat(courseStatus(course)).isEqualTo("DELETED");
        assertThat(entryCount(course)).isZero();
    }

    @Test
    void keepsNewestVisibility() {
        UUID member = UUID.randomUUID();

        publish(new MemberVisibilityChangedEvent(UUID.randomUUID(), Instant.now(), member, false, 2));
        publish(new MemberVisibilityChangedEvent(UUID.randomUUID(), Instant.now(), member, true, 1));   // 늦게 온 옛 버전
        assertThat(visible(member)).isFalse();

        publish(new MemberVisibilityChangedEvent(UUID.randomUUID(), Instant.now(), member, true, 3));
        assertThat(visible(member)).isTrue();
    }

    @Test
    void deletesRankingRecordsOfWithdrawnMember() {
        UUID course = UUID.randomUUID();
        UUID member = UUID.randomUUID();
        insertEntry(course, member);
        insertEntry(course, UUID.randomUUID());
        MemberWithdrawnEvent withdrawn = new MemberWithdrawnEvent(UUID.randomUUID(), Instant.now(), member, Instant.now());

        publish(withdrawn);
        publish(withdrawn);   // 중복

        assertThat(entryCount(course)).isOne();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM ranking.withdrawn_members WHERE member_id = ?", Long.class, member))
                .isOne();
    }

    private void publish(Object event) {
        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(jdbc.queryForObject("SELECT count(*) FROM common.event_publication", Long.class)).isZero());
    }

    private static CourseStatusChangedEvent courseStatus(UUID courseId, CourseStatus status, long version) {
        return new CourseStatusChangedEvent(UUID.randomUUID(), Instant.now(), courseId, status, CourseStatusReason.EXPIRED, version);
    }

    private void insertEntry(UUID courseId) {
        insertEntry(courseId, UUID.randomUUID());
    }

    private void insertEntry(UUID courseId, UUID memberId) {
        jdbc.update("""
                INSERT INTO ranking.course_ranking_entries (run_record_id, course_id, member_id, course_elapsed_seconds,
                    course_distance_meters, completed_at, registered_at, created_at, updated_at)
                VALUES (?, ?, ?, 300, 1000, now(), now(), now(), now())""", UUID.randomUUID(), courseId, memberId);
    }

    private String courseStatus(UUID courseId) {
        return jdbc.queryForObject("SELECT status FROM ranking.course_status_copies WHERE course_id = ?", String.class, courseId);
    }

    private long entryCount(UUID courseId) {
        return jdbc.queryForObject("SELECT count(*) FROM ranking.course_ranking_entries WHERE course_id = ?", Long.class, courseId);
    }

    private boolean visible(UUID memberId) {
        return jdbc.queryForObject("SELECT visible FROM ranking.member_visibility_copies WHERE member_id = ?", Boolean.class, memberId);
    }
    private RunSessionEndedEvent ended(UUID record, UUID member) {
        Instant at=Instant.now();
        return new RunSessionEndedEvent(UUID.randomUUID(),at,record,member,null,false,1234.567,0,0,0,0,false,null,at,at,at,"2026-10-14");
    }
    @Test void runDistanceCopiesSurviveDuplicateAndReversedDeliveryWithoutResurrection() {
        UUID member=UUID.randomUUID(),record=UUID.randomUUID();
        RunSessionEndedEvent ended=ended(record,member);
        publish(ended); publish(ended);
        assertThat(jdbc.queryForObject("SELECT sum(distance_meters) FROM ranking.distance_run_records WHERE member_id=? AND NOT deleted",Double.class,member)).isEqualTo(1234.567);
        RunRecordDeletedEvent deleted=new RunRecordDeletedEvent(UUID.randomUUID(),Instant.now(),record,member,null,false,ended.distanceMeters(),0,ended.startedAt(),ended.endedAt(),ended.registeredAt());
        publish(deleted); publish(deleted); publish(ended);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM ranking.distance_run_records WHERE member_id=? AND NOT deleted",Long.class,member)).isZero();
        UUID reversed=UUID.randomUUID();
        publish(new RunRecordDeletedEvent(UUID.randomUUID(),Instant.now(),reversed,member,null,false,10,0,Instant.now(),Instant.now(),Instant.now()));
        publish(ended(reversed,member));
        assertThat(jdbc.queryForObject("SELECT deleted FROM ranking.distance_run_records WHERE run_record_id=?",Boolean.class,reversed)).isTrue();
    }
    @Test void withdrawalAndDelayedRunEventsCannotRestoreDistanceCopies() {
        UUID member=UUID.randomUUID(),record=UUID.randomUUID();
        RunSessionEndedEvent ended=ended(record,member);
        publish(ended);
        publish(new MemberWithdrawnEvent(UUID.randomUUID(),Instant.now(),member,Instant.now()));
        publish(ended); publish(ended(UUID.randomUUID(),member));
        assertThat(jdbc.queryForObject("SELECT count(*) FROM ranking.distance_run_records WHERE member_id=?",Long.class,member)).isZero();
    }

}
