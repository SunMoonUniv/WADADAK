package com.wadadak.notification.internal.setting;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.UUID;

/** 알림 설정({@code notification.notification_settings}). 행이 없으면 기본값이다. 이벤트 처리도 쓰므로 {@code public}이다 */
@Repository
@RequiredArgsConstructor
public class NotificationSettingRepository {

    private final JdbcClient jdbc;

    public NotificationSettings find(UUID memberId) {
        return jdbc.sql("SELECT course_expiring_soon FROM notification.notification_settings WHERE member_id = :memberId")
                .param("memberId", memberId)
                .query((rs, rowNum) -> new NotificationSettings(rs.getBoolean("course_expiring_soon")))
                .optional()
                .orElse(NotificationSettings.DEFAULT);
    }

    void save(UUID memberId, NotificationSettings settings, Instant now) {
        jdbc.sql("""
                        INSERT INTO notification.notification_settings (member_id, course_expiring_soon, created_at, updated_at)
                        VALUES (:memberId, :courseExpiringSoon, :now, :now)
                        ON CONFLICT (member_id) DO UPDATE
                            SET course_expiring_soon = EXCLUDED.course_expiring_soon, updated_at = EXCLUDED.updated_at""")
                .param("memberId", memberId)
                .param("courseExpiringSoon", settings.courseExpiringSoon())
                .param("now", OffsetDateTime.ofInstant(now, ZoneOffset.UTC))
                .update();
    }

    /** 회원 탈퇴 */
    public void deleteForMember(UUID memberId) {
        jdbc.sql("DELETE FROM notification.notification_settings WHERE member_id = :memberId")
                .param("memberId", memberId)
                .update();
    }
}
