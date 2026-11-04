package com.wadadak.notification.internal.delivery;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.notification.internal.push.PushMessage;
import com.wadadak.notification.internal.push.PushResult;
import com.wadadak.notification.internal.push.PushSender;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

/**
 * 발송 작업. FCM 대신 가짜 {@link PushSender}가 정해 준 결과를 돌려준다.
 * 발송 작업은 DB 전체의 보낼 줄을 보므로, 매번 알림 · 기기를 모두 지우고 시작한다(notification 시험끼리만 쓰는 표다).
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class PushDispatcherTest {

    @MockitoBean
    PushSender sender;

    @Autowired
    PushDispatcher dispatcher;

    @Autowired
    NotificationStore store;

    @Autowired
    JdbcTemplate jdbc;

    @BeforeEach
    void clean() {
        jdbc.update("DELETE FROM notification.notifications");
        jdbc.update("DELETE FROM notification.device_tokens");
        given(sender.send(anyString(), any())).willReturn(PushResult.sent());
    }

    @Test
    void sendsOnceAndRecordsIt() {
        UUID member = UUID.randomUUID();
        device(member, "phone");
        enqueue(member, Instant.now().plus(Duration.ofHours(12)));

        assertThat(dispatcher.dispatchDue()).isOne();
        assertThat(dispatcher.dispatchDue()).as("보낸 줄은 다시 보내지 않는다").isZero();

        String notificationId = jdbc.queryForObject("SELECT id::text FROM notification.notifications WHERE member_id = ?",
                String.class, member);
        // 앱이 푸시를 눌러 알림함의 그 알림을 읽음으로 바꾸도록 알림 ID를 붙인다
        verify(sender, times(1)).send(eq("phone"), eq(new PushMessage("내 코스 만료 임박", "‘한강’ 코스가 내일 만료돼요.",
                Map.of("type", "COURSE_EXPIRING_SOON", "courseId", "c-1", "notificationId", notificationId))));
        Map<String, Object> line = delivery(member);
        assertThat(line.get("status")).isEqualTo("SENT");
        assertThat(line.get("attempts")).isEqualTo(1);
        assertThat(line.get("sent_at")).isNotNull();
    }

    @Test
    void forgetsATokenThatNoLongerExists() {
        UUID member = UUID.randomUUID();
        device(member, "uninstalled");
        enqueue(member, Instant.now().plus(Duration.ofHours(12)));
        given(sender.send(eq("uninstalled"), any())).willReturn(PushResult.invalidToken("404 UNREGISTERED"));

        dispatcher.dispatchDue();

        assertThat(jdbc.queryForObject("SELECT count(*) FROM notification.device_tokens WHERE member_id = ?", Long.class, member))
                .isZero();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM notification.deliveries", Long.class))
                .as("그 기기에 보낼 줄도 함께 지워진다").isZero();
    }

    @Test
    void triesAgainLaterOnATemporaryFailure() {
        UUID member = UUID.randomUUID();
        device(member, "phone");
        enqueue(member, Instant.now().plus(Duration.ofHours(12)));
        given(sender.send(eq("phone"), any())).willReturn(PushResult.retryLater("503 UNAVAILABLE"));

        dispatcher.dispatchDue();
        assertThat(dispatcher.dispatchDue()).as("1분 뒤까지는 다시 보내지 않는다").isZero();

        Map<String, Object> line = delivery(member);
        assertThat(line.get("status")).isEqualTo("PENDING");
        assertThat(line.get("attempts")).isEqualTo(1);
        assertThat(line.get("last_error")).isEqualTo("503 UNAVAILABLE");
        assertThat(((Timestamp) line.get("next_attempt_at")).toInstant())
                .isCloseTo(Instant.now().plus(Duration.ofMinutes(1)), within(Duration.ofSeconds(10)));
    }

    @Test
    void givesUpOnARejectedMessageButKeepsTheToken() {
        UUID member = UUID.randomUUID();
        device(member, "phone");
        enqueue(member, Instant.now().plus(Duration.ofHours(12)));
        given(sender.send(eq("phone"), any())).willReturn(PushResult.rejected("400 INVALID_ARGUMENT"));

        dispatcher.dispatchDue();

        assertThat(delivery(member).get("status")).isEqualTo("FAILED");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM notification.device_tokens WHERE member_id = ?", Long.class, member))
                .isOne();
    }

    @Test
    void doesNotSendLateOrToADeviceSomeoneElseNowUses() {
        UUID late = UUID.randomUUID();
        device(late, "late-phone");
        enqueue(late, Instant.now().minusSeconds(1)); // 보낼 기한이 지났다
        UUID before = UUID.randomUUID();
        UUID tokenId = device(before, "shared-phone");
        enqueue(before, Instant.now().plus(Duration.ofHours(12)));
        // 그 사이 같은 기기에 다른 계정이 로그인했다(동시에 등록돼 예전 줄이 남은 경우)
        jdbc.update("UPDATE notification.device_tokens SET member_id = ? WHERE id = ?", UUID.randomUUID(), tokenId);

        dispatcher.dispatchDue();

        verify(sender, never()).send(anyString(), any());
        assertThat(delivery(late).get("status")).isEqualTo("EXPIRED");
        assertThat(delivery(before).get("status")).isEqualTo("EXPIRED");
    }

    @Test
    void stopsTheRoundWhenFailuresKeepComing() {
        for (int i = 0; i < 5; i++) {
            UUID member = UUID.randomUUID();
            device(member, "down-" + i);
            enqueue(member, Instant.now().plus(Duration.ofHours(12)));
        }
        given(sender.send(anyString(), any())).willReturn(PushResult.retryLater("연결 실패"));

        assertThat(dispatcher.dispatchDue()).as("3번 이어 실패하면 멈춘다").isEqualTo(PushDispatcher.STOP_AFTER_RETRIES);
        verify(sender, times(PushDispatcher.STOP_AFTER_RETRIES)).send(anyString(), any());
    }

    @Test
    void waitsLongerAfterEachFailure() {
        assertThat(PushDispatcher.backoff(1)).isEqualTo(Duration.ofMinutes(1));
        assertThat(PushDispatcher.backoff(2)).isEqualTo(Duration.ofMinutes(2));
        assertThat(PushDispatcher.backoff(5)).isEqualTo(Duration.ofMinutes(16));
        assertThat(PushDispatcher.backoff(6)).isEqualTo(Duration.ofMinutes(30));
        assertThat(PushDispatcher.backoff(40)).isEqualTo(Duration.ofMinutes(30));
    }

    private UUID device(UUID member, String token) {
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO notification.device_tokens VALUES (?, ?, ?, 'ANDROID', now(), now())", id, member, token);
        return id;
    }

    private void enqueue(UUID member, Instant sendUntil) {
        store.enqueue(new NotificationDraft(member, NotificationKind.COURSE_EXPIRING_SOON, "key-" + member,
                "내 코스 만료 임박", "‘한강’ 코스가 내일 만료돼요.", Map.of("type", "COURSE_EXPIRING_SOON", "courseId", "c-1"),
                sendUntil), Instant.now(), true);
    }

    private Map<String, Object> delivery(UUID member) {
        return jdbc.queryForMap("""
                SELECT d.* FROM notification.deliveries d
                JOIN notification.notifications n ON n.id = d.notification_id
                WHERE n.member_id = ?""", member);
    }
}
