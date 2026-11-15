package com.wadadak.notification.internal.inbox;

import com.wadadak.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 알림함 API(Figma F3 알림 센터 · A2 종 아이콘). 회원은 매번 새 ID라 다른 시험과 섞이지 않는다 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class NotificationInboxApiTest {

    private static final String INBOX = "/api/v1/notifications";

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    NotificationInboxRepository repository;

    @Test
    void listsMyRecentNotificationsNewestFirstPageByPage() {
        UUID me = UUID.randomUUID();
        UUID older = notification(me, "1시간 전", Duration.ofHours(1), false);
        UUID newer = notification(me, "12분 전", Duration.ofMinutes(12), false);
        UUID read = notification(me, "어제", Duration.ofDays(1), true);
        notification(me, "31일 전", Duration.ofDays(31), false); // 30일이 지나 보이지 않는다
        notification(UUID.randomUUID(), "남의 알림", Duration.ofMinutes(1), false);

        var first = assertThat(mvc.get().uri(INBOX + "?size=2").with(member(me)).exchange()).hasStatusOk().bodyJson();
        first.extractingPath("$.data.content[*].id").asArray().containsExactly(newer.toString(), older.toString());
        first.extractingPath("$.data.content[0].body").isEqualTo("12분 전");
        first.extractingPath("$.data.content[0].read").isEqualTo(false);
        first.extractingPath("$.data.content[0].data.courseId").isEqualTo("c-1");
        first.extractingPath("$.data.nextCursor").isEqualTo("2");

        var second = assertThat(mvc.get().uri(INBOX + "?size=2&cursor=2").with(member(me)).exchange()).hasStatusOk().bodyJson();
        second.extractingPath("$.data.content[*].id").asArray().containsExactly(read.toString());
        second.extractingPath("$.data.content[0].read").isEqualTo(true);
        second.extractingPath("$.data.nextCursor").isNull();
    }

    @Test
    void readingOneOrAllClearsTheUnreadCount() {
        UUID me = UUID.randomUUID();
        UUID first = notification(me, "첫 알림", Duration.ofMinutes(1), false);
        notification(me, "둘째 알림", Duration.ofMinutes(2), false);
        notification(me, "오래된 알림", Duration.ofDays(31), false); // 30일 지난 알림은 세지 않는다
        UUID theirs = notification(UUID.randomUUID(), "남의 알림", Duration.ofMinutes(1), false);

        assertUnread(me, 2);

        assertThat(mvc.put().uri(INBOX + "/" + first + "/read").with(member(me)).exchange()).hasStatusOk();
        assertThat(mvc.put().uri(INBOX + "/" + first + "/read").with(member(me)).exchange()).as("다시 읽어도 오류가 아니다").hasStatusOk();
        assertUnread(me, 1);

        assertThat(mvc.put().uri(INBOX + "/" + theirs + "/read").with(member(me)).exchange()).as("남의 알림은 그냥 넘어간다").hasStatusOk();
        assertThat(readAt(theirs)).isNull();

        assertThat(mvc.put().uri(INBOX + "/read-all").with(member(me)).exchange()).hasStatusOk();
        assertUnread(me, 0);
        assertThat(readAt(theirs)).as("모두 읽음은 내 알림만").isNull();
    }

    @Test
    void deletesNotificationsOlderThanThirtyDaysWithTheirDeliveries() {
        UUID me = UUID.randomUUID();
        UUID old = notification(me, "31일 전", Duration.ofDays(31), false);
        UUID recent = notification(me, "29일 전", Duration.ofDays(29), false);
        UUID token = UUID.randomUUID();
        jdbc.update("INSERT INTO notification.device_tokens VALUES (?, ?, ?, 'ANDROID', now(), now())", token, me, "t-" + me);
        jdbc.update("""
                INSERT INTO notification.deliveries (notification_id, device_token_id, status, attempts, next_attempt_at, created_at, updated_at)
                VALUES (?, ?, 'SENT', 1, now(), now(), now())""", old, token);

        repository.deleteCreatedBefore(Instant.now().minus(NotificationInboxService.KEEP_FOR));

        assertThat(jdbc.queryForList("SELECT id FROM notification.notifications WHERE member_id = ?", UUID.class, me))
                .containsExactly(recent);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM notification.deliveries WHERE device_token_id = ?", Long.class, token))
                .as("보낼 줄도 함께 지워진다").isZero();
    }

    @Test
    void rejectsABadCursorOrId() {
        UUID me = UUID.randomUUID();

        assertThat(mvc.get().uri(INBOX + "?cursor=abc").with(member(me)).exchange())
                .hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
        assertThat(mvc.put().uri(INBOX + "/not-a-uuid/read").with(member(me)).exchange())
                .hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    @Test
    void aWithdrawnMemberWithAStillValidTokenIsAskedToLogInAgain() {
        UUID me = UUID.randomUUID();
        jdbc.update("INSERT INTO notification.withdrawn_members VALUES (?, now(), now(), now())", me);

        assertThat(mvc.get().uri(INBOX).with(member(me)).exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED).bodyJson().extractingPath("$.code").isEqualTo("COMMON-002");
        assertThat(mvc.get().uri(INBOX + "/unread-count").with(member(me)).exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(mvc.put().uri(INBOX + "/read-all").with(member(me)).exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void needsLogin() {
        assertThat(mvc.get().uri(INBOX).exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(mvc.get().uri(INBOX + "/unread-count").exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    /** {@code ago} 전에 만든 알림 한 건. 본문으로 어느 알림인지 알아본다 */
    private UUID notification(UUID member, String body, Duration ago, boolean read) {
        UUID id = UUID.randomUUID();
        Timestamp createdAt = Timestamp.from(Instant.now().minus(ago));
        jdbc.update("""
                        INSERT INTO notification.notifications
                            (id, member_id, kind, dedupe_key, title, body, data, send_until, created_at, updated_at, read_at)
                        VALUES (?, ?, 'COURSE_EXPIRING_SOON', ?, '내 코스 만료 임박', ?,
                                '{"type": "COURSE_EXPIRING_SOON", "courseId": "c-1"}'::jsonb, ?, ?, ?, ?)""",
                id, member, "test/" + id, body, createdAt, createdAt, createdAt, read ? createdAt : null);
        return id;
    }

    private void assertUnread(UUID member, int count) {
        assertThat(mvc.get().uri(INBOX + "/unread-count").with(member(member)).exchange())
                .hasStatusOk().bodyJson().extractingPath("$.data.count").isEqualTo(count);
    }

    private Timestamp readAt(UUID notification) {
        return jdbc.queryForObject("SELECT read_at FROM notification.notifications WHERE id = ?", Timestamp.class, notification);
    }

    private static RequestPostProcessor member(UUID memberId) {
        return jwt().jwt(j -> j.subject(memberId.toString()));
    }
}
