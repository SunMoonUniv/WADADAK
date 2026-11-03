package com.wadadak.notification.internal;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.event.course.CourseExpiringSoonEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
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
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

/**
 * 이벤트로 알림을 만들고 지우는지 본다. 이벤트는 커밋 뒤 다른 스레드에서 처리되므로 아웃박스가 빌 때까지 기다린다
 * (review · ranking과 같은 방식). 회원 · 코스는 매번 새 ID라 다른 시험과 섞이지 않는다.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class NotificationEventHandlerTest {

    @Autowired
    TransactionTemplate transactionTemplate;

    @Autowired
    ApplicationEventPublisher publisher;

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void makesOneNotificationWithALineForEachDeviceEvenIfTheEventComesTwice() {
        UUID creator = UUID.randomUUID();
        device(creator, "phone-" + creator);
        device(creator, "tablet-" + creator);
        device(UUID.randomUUID(), "someone-else-" + creator); // 다른 회원의 기기에는 가지 않는다
        CourseExpiringSoonEvent event = expiringSoon(creator, 7, Instant.now().plus(Duration.ofDays(7)));

        publish(event);
        publish(event); // 같은 이벤트가 다시 온다(아웃박스 재전송)
        publish(new CourseExpiringSoonEvent(UUID.randomUUID(), Instant.now(), event.courseId(), creator, "한강 야경",
                event.expiresAt(), 7)); // 이벤트 ID만 다른 같은 일(배치를 두 번 돌림)

        Map<String, Object> notification = jdbc.queryForMap(
                "SELECT * FROM notification.notifications WHERE member_id = ?", creator);
        assertThat(notification.get("kind")).isEqualTo("COURSE_EXPIRING_SOON");
        assertThat(notification.get("title")).isEqualTo("내 코스 만료 임박");
        assertThat(notification.get("body")).isEqualTo("‘한강 야경’ 코스가 7일 뒤 만료돼요.");
        assertThat(jdbc.queryForObject("SELECT data->>'courseId' FROM notification.notifications WHERE member_id = ?",
                String.class, creator)).isEqualTo(event.courseId().toString());
        assertThat(jdbc.queryForObject("""
                        SELECT count(*) FROM notification.deliveries d
                        JOIN notification.notifications n ON n.id = d.notification_id
                        WHERE n.member_id = ? AND d.status = 'PENDING'""", Long.class, creator))
                .as("기기 두 대에 한 줄씩").isEqualTo(2);
    }

    @Test
    void tomorrowReadsAsTomorrow() {
        UUID creator = UUID.randomUUID();

        publish(expiringSoon(creator, 1, Instant.now().plus(Duration.ofDays(1))));

        assertThat(jdbc.queryForObject("SELECT body FROM notification.notifications WHERE member_id = ?", String.class, creator))
                .isEqualTo("‘한강 야경’ 코스가 내일 만료돼요.");
    }

    @Test
    void skipsWhenTurnedOffWithdrawnOrTooLate() {
        UUID turnedOff = UUID.randomUUID();
        jdbc.update("INSERT INTO notification.notification_settings VALUES (?, FALSE, now(), now())", turnedOff);
        UUID withdrawn = UUID.randomUUID();
        jdbc.update("INSERT INTO notification.withdrawn_members VALUES (?, now(), now(), now())", withdrawn);
        UUID late = UUID.randomUUID();

        publish(expiringSoon(turnedOff, 7, Instant.now().plus(Duration.ofDays(7))));
        publish(expiringSoon(withdrawn, 7, Instant.now().plus(Duration.ofDays(7))));
        // 오전 9시 이벤트가 하루 늦게 처리됐다(서버가 꺼져 있다 켜짐). 보낼 기한(12시간)이 지났다
        publish(new CourseExpiringSoonEvent(UUID.randomUUID(), Instant.now().minus(Duration.ofDays(1)), UUID.randomUUID(),
                late, "한강 야경", Instant.now().plus(Duration.ofDays(6)), 7));

        for (UUID member : new UUID[]{turnedOff, withdrawn, late}) {
            assertThat(notifications(member)).isZero();
        }
    }

    @Test
    void withdrawalRemovesEverythingAndBlocksLaterEvents() {
        UUID member = UUID.randomUUID();
        device(member, "phone-" + member);
        jdbc.update("INSERT INTO notification.notification_settings VALUES (?, TRUE, now(), now())", member);
        publish(expiringSoon(member, 7, Instant.now().plus(Duration.ofDays(7))));
        assertThat(notifications(member)).isOne();

        MemberWithdrawnEvent withdrawn = new MemberWithdrawnEvent(UUID.randomUUID(), Instant.now(), member, Instant.now());
        publish(withdrawn);
        publish(withdrawn); // 다시 와도 같다

        assertThat(notifications(member)).isZero();
        assertThat(count("notification.device_tokens", member)).isZero();
        assertThat(count("notification.notification_settings", member)).isZero();
        assertThat(count("notification.withdrawn_members", member)).isOne();
        // 탈퇴 회원이 등록한 코스는 남아 만료 임박이 또 올 수 있다. 받지 않는다
        publish(expiringSoon(member, 1, Instant.now().plus(Duration.ofDays(1))));
        assertThat(notifications(member)).isZero();
    }

    private void device(UUID member, String token) {
        jdbc.update("INSERT INTO notification.device_tokens VALUES (?, ?, ?, 'ANDROID', now(), now())",
                UUID.randomUUID(), member, token);
    }

    private long notifications(UUID member) {
        return count("notification.notifications", member);
    }

    private long count(String table, UUID member) {
        return jdbc.queryForObject("SELECT count(*) FROM " + table + " WHERE member_id = ?", Long.class, member);
    }

    private static CourseExpiringSoonEvent expiringSoon(UUID creator, int daysLeft, Instant expiresAt) {
        return new CourseExpiringSoonEvent(UUID.randomUUID(), Instant.now(), UUID.randomUUID(), creator, "한강 야경",
                expiresAt, daysLeft);
    }

    private void publish(Object event) {
        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(jdbc.queryForObject("SELECT count(*) FROM common.event_publication", Long.class)).isZero());
    }
}
