package com.wadadak.notification.internal.inbox;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 알림함이 읽고 바꾸는 {@code notification.notifications}. 알림을 만드는 쪽은 {@code NotificationStore}(delivery)다.
 *
 * <p>[왜 따로 두나] 만들기 · 보내기(delivery)와 보기 · 읽음(inbox)은 바뀌는 이유가 달라서 나눴다. 같은 표를 쓰지만
 * 모두 notification 모듈 안이라 모듈 경계(개발 정책 4.3)는 그대로다.
 *
 * <p>모든 쿼리는 {@code member_id}로 본인 알림만 본다. 남의 알림 ID를 보내도 바뀌지 않는다.
 */
@Repository
@RequiredArgsConstructor
class NotificationInboxRepository {

    private static final TypeReference<Map<String, String>> DATA = new TypeReference<>() {
    };

    private final JdbcClient jdbc;
    private final JsonMapper json;

    /**
     * {@code since} 뒤에 만든 알림을 최신순으로 {@code offset}부터 {@code limit}개. 만든 시각이 같으면 ID가 큰(나중에 만든, UUIDv7) 것이 먼저다.
     * 인덱스 {@code notifications_member_id_created_at_idx}가 이 순서 그대로다.
     */
    List<NotificationItem> list(UUID memberId, Instant since, int offset, int limit) {
        return jdbc.sql("""
                        SELECT id, kind, title, body, data::text AS data, created_at, read_at IS NOT NULL AS read
                        FROM notification.notifications
                        WHERE member_id = :memberId AND created_at >= :since
                        ORDER BY created_at DESC, id DESC
                        OFFSET :offset LIMIT :limit""")
                .param("memberId", memberId)
                .param("since", timestamp(since))
                .param("offset", offset)
                .param("limit", limit)
                .query((rs, rowNum) -> new NotificationItem(
                        rs.getObject("id", UUID.class),
                        rs.getString("kind"),
                        rs.getString("title"),
                        rs.getString("body"),
                        json.readValue(rs.getString("data"), DATA),
                        rs.getObject("created_at", OffsetDateTime.class).toInstant(),
                        rs.getBoolean("read")))
                .list();
    }

    long unreadCount(UUID memberId, Instant since) {
        return jdbc.sql("""
                        SELECT count(*) FROM notification.notifications
                        WHERE member_id = :memberId AND created_at >= :since AND read_at IS NULL""")
                .param("memberId", memberId)
                .param("since", timestamp(since))
                .query(Long.class)
                .single();
    }

    /** 한 건을 읽음으로. 이미 읽었으면 처음 읽은 시각을 그대로 둔다 */
    void markRead(UUID memberId, UUID notificationId, Instant now) {
        jdbc.sql("""
                        UPDATE notification.notifications SET read_at = :now, updated_at = :now
                        WHERE id = :id AND member_id = :memberId AND read_at IS NULL""")
                .param("now", timestamp(now))
                .param("id", notificationId)
                .param("memberId", memberId)
                .update();
    }

    /** 안 읽은 알림을 모두 읽음으로(`모두 읽음`) */
    void markAllRead(UUID memberId, Instant now) {
        jdbc.sql("""
                        UPDATE notification.notifications SET read_at = :now, updated_at = :now
                        WHERE member_id = :memberId AND read_at IS NULL""")
                .param("now", timestamp(now))
                .param("memberId", memberId)
                .update();
    }

    /**
     * {@code before}보다 먼저 만든 알림을 지운다(모든 회원). 보낼 줄도 함께 지워진다(ON DELETE CASCADE). 지운 수를 돌려준다.
     * 하루 한 번이고 하루치만 지워서 인덱스 없이 표를 훑어도 된다.
     */
    int deleteCreatedBefore(Instant before) {
        return jdbc.sql("DELETE FROM notification.notifications WHERE created_at < :before")
                .param("before", timestamp(before))
                .update();
    }

    /** PostgreSQL 드라이버는 Instant를 바로 받지 못해서 UTC 시각으로 바꿔 넘긴다 */
    private static OffsetDateTime timestamp(Instant instant) {
        return OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
