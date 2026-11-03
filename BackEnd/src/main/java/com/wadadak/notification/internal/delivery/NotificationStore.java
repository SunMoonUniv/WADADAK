package com.wadadak.notification.internal.delivery;

import com.wadadak.common.entity.UuidV7;
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
 * 알림({@code notifications})과 기기별 발송 줄({@code deliveries}).
 *
 * <p>[흐름] 이벤트 처리가 {@link #enqueue}로 알림 한 건과 기기마다 PENDING 줄을 만든다(이벤트 처리 트랜잭션 안).
 * 그 뒤 발송 작업({@link PushDispatcher})이 {@link #due}로 차례가 된 줄을 꺼내 보내고 결과를 적는다.
 * 보내기(네트워크)를 이벤트 처리에서 떼어 놓아서, FCM이 느리거나 멈춰도 다른 모듈의 이벤트 처리가 밀리지 않는다.
 */
@Repository
@RequiredArgsConstructor
public class NotificationStore {

    private static final TypeReference<Map<String, String>> DATA = new TypeReference<>() {
    };

    private final JdbcClient jdbc;
    private final JsonMapper json;

    /**
     * 알림을 만들고 그 회원의 기기마다 보낼 줄을 만든다. 같은 {@code (kind, dedupeKey)} 알림이 이미 있으면 아무것도 하지 않고
     * false를 돌려준다(이벤트가 다시 와도 한 번만 보낸다, 개발 정책 5.4 삽입형). 기기가 없으면 알림만 남는다.
     */
    public boolean enqueue(NotificationDraft draft, Instant now) {
        UUID id = UuidV7.create();
        int inserted = jdbc.sql("""
                        INSERT INTO notification.notifications
                            (id, member_id, kind, dedupe_key, title, body, data, send_until, created_at, updated_at)
                        VALUES (:id, :memberId, :kind, :dedupeKey, :title, :body, CAST(:data AS jsonb), :sendUntil, :now, :now)
                        ON CONFLICT (kind, dedupe_key) DO NOTHING""")
                .param("id", id)
                .param("memberId", draft.memberId())
                .param("kind", draft.kind().name())
                .param("dedupeKey", draft.dedupeKey())
                .param("title", draft.title())
                .param("body", draft.body())
                .param("data", json.writeValueAsString(draft.data()))
                .param("sendUntil", timestamp(draft.sendUntil()))
                .param("now", timestamp(now))
                .update();
        if (inserted == 0) {
            return false;
        }
        jdbc.sql("""
                        INSERT INTO notification.deliveries
                            (notification_id, device_token_id, status, attempts, next_attempt_at, created_at, updated_at)
                        SELECT :id, t.id, 'PENDING', 0, :now, :now, :now
                        FROM notification.device_tokens t
                        WHERE t.member_id = :memberId""")
                .param("id", id)
                .param("memberId", draft.memberId())
                .param("now", timestamp(now))
                .update();
        return true;
    }

    /** 보낼 시각이 된 PENDING 줄을 오래 기다린 것부터 {@code limit}개 */
    List<DueDelivery> due(Instant now, int limit) {
        return jdbc.sql("""
                        SELECT d.notification_id, d.device_token_id, d.attempts, t.token, t.member_id = n.member_id AS same_member,
                               n.title, n.body, n.data::text AS data, n.send_until
                        FROM notification.deliveries d
                        JOIN notification.notifications n ON n.id = d.notification_id
                        JOIN notification.device_tokens t ON t.id = d.device_token_id
                        WHERE d.status = 'PENDING' AND d.next_attempt_at <= :now
                        ORDER BY d.next_attempt_at
                        LIMIT :limit""")
                .param("now", timestamp(now))
                .param("limit", limit)
                .query((rs, rowNum) -> new DueDelivery(
                        rs.getObject("notification_id", UUID.class),
                        rs.getObject("device_token_id", UUID.class),
                        rs.getString("token"),
                        rs.getBoolean("same_member"),
                        rs.getInt("attempts"),
                        rs.getString("title"),
                        rs.getString("body"),
                        json.readValue(rs.getString("data"), DATA),
                        rs.getObject("send_until", OffsetDateTime.class).toInstant()))
                .list();
    }

    void markSent(DueDelivery delivery, Instant now) {
        finish(delivery, "SENT", null, now, now);
    }

    /** 다시 보내도 안 되는 실패. 토큰은 그대로 둔다 */
    void markFailed(DueDelivery delivery, String error, Instant now) {
        finish(delivery, "FAILED", error, null, now);
    }

    /** 기한이 지났거나 기기 주인이 바뀌었다. 보내지 않고 끝낸다 */
    void markExpired(DueDelivery delivery, Instant now) {
        jdbc.sql("""
                        UPDATE notification.deliveries SET status = 'EXPIRED', updated_at = :now
                        WHERE notification_id = :notificationId AND device_token_id = :deviceTokenId AND status = 'PENDING'""")
                .param("now", timestamp(now))
                .param("notificationId", delivery.notificationId())
                .param("deviceTokenId", delivery.deviceTokenId())
                .update();
    }

    /** 잠깐의 실패. 시도 수를 올리고 {@code nextAttemptAt}에 다시 보낸다 */
    void retryLater(DueDelivery delivery, Instant nextAttemptAt, String error, Instant now) {
        jdbc.sql("""
                        UPDATE notification.deliveries
                        SET attempts = attempts + 1, next_attempt_at = :nextAttemptAt, last_error = :error, updated_at = :now
                        WHERE notification_id = :notificationId AND device_token_id = :deviceTokenId AND status = 'PENDING'""")
                .param("nextAttemptAt", timestamp(nextAttemptAt))
                .param("error", truncate(error))
                .param("now", timestamp(now))
                .param("notificationId", delivery.notificationId())
                .param("deviceTokenId", delivery.deviceTokenId())
                .update();
    }

    /** 회원 탈퇴. 알림을 지우면 보낼 줄도 함께 지워진다(ON DELETE CASCADE) */
    public void deleteForMember(UUID memberId) {
        jdbc.sql("DELETE FROM notification.notifications WHERE member_id = :memberId")
                .param("memberId", memberId)
                .update();
    }

    /** PENDING인 줄만 바꾼다. 그 사이 다른 처리(탈퇴 · 기한 지남)가 끝낸 줄을 되살리지 않는다 */
    private void finish(DueDelivery delivery, String status, String error, Instant sentAt, Instant now) {
        jdbc.sql("""
                        UPDATE notification.deliveries
                        SET status = :status, attempts = attempts + 1, last_error = :error, sent_at = :sentAt, updated_at = :now
                        WHERE notification_id = :notificationId AND device_token_id = :deviceTokenId AND status = 'PENDING'""")
                .param("status", status)
                .param("error", truncate(error))
                .param("sentAt", sentAt == null ? null : timestamp(sentAt))
                .param("now", timestamp(now))
                .param("notificationId", delivery.notificationId())
                .param("deviceTokenId", delivery.deviceTokenId())
                .update();
    }

    /** {@code last_error}는 200자까지다 */
    private static String truncate(String error) {
        return error == null || error.length() <= 200 ? error : error.substring(0, 200);
    }

    /** PostgreSQL 드라이버는 Instant를 바로 받지 못해서 UTC 시각으로 바꿔 넘긴다 */
    private static OffsetDateTime timestamp(Instant instant) {
        return OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
