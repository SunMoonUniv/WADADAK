package com.wadadak.notification.internal.device;

import com.wadadak.common.entity.UuidV7;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.UUID;

/**
 * 기기 푸시 토큰({@code notification.device_tokens}). 토큰을 지우면 그 기기에 보낼 줄({@code deliveries})도
 * DB가 함께 지운다(ON DELETE CASCADE, 같은 스키마 안이라 FK를 건다).
 *
 * <p>발송 작업(만료된 토큰 지우기)과 이벤트 처리(탈퇴)도 쓰므로 {@code public}이다.
 */
@Repository
@RequiredArgsConstructor
public class DeviceTokenRepository {

    /** 한 회원이 둘 수 있는 기기 수. 넘으면 오래 등록하지 않은 기기부터 지운다 */
    static final int MAX_DEVICES_PER_MEMBER = 10;

    private final JdbcClient jdbc;

    /**
     * 토큰을 이 회원의 기기로 등록한다. 이미 있으면 등록 시각만 새로 한다.
     *
     * <p>같은 기기에 다른 계정이 로그인하면 토큰이 같다. 그 기기는 이제 이 회원 것이라 예전 계정의 줄을 먼저 지운다
     * (예전 계정에 보내려던 줄도 함께 지워진다). 동시에 두 계정이 같은 토큰을 등록해도 마지막 등록이 이긴다
     * (ON CONFLICT … SET member_id).
     */
    void register(UUID memberId, String token, DevicePlatform platform, Instant now) {
        jdbc.sql("DELETE FROM notification.device_tokens WHERE token = :token AND member_id <> :memberId")
                .param("token", token)
                .param("memberId", memberId)
                .update();
        jdbc.sql("""
                        INSERT INTO notification.device_tokens (id, member_id, token, platform, created_at, updated_at)
                        VALUES (:id, :memberId, :token, :platform, :now, :now)
                        ON CONFLICT (token) DO UPDATE
                            SET member_id = EXCLUDED.member_id, platform = EXCLUDED.platform, updated_at = EXCLUDED.updated_at""")
                .param("id", UuidV7.create())
                .param("memberId", memberId)
                .param("token", token)
                .param("platform", platform.name())
                .param("now", timestamp(now))
                .update();
        // 오래된 기기 정리. 앱을 지웠다 깔면 토큰이 새로 생겨서, 정리하지 않으면 안 쓰는 토큰이 계속 쌓인다
        jdbc.sql("""
                        DELETE FROM notification.device_tokens
                        WHERE member_id = :memberId
                          AND id NOT IN (SELECT id FROM notification.device_tokens WHERE member_id = :memberId
                                         ORDER BY updated_at DESC, id DESC LIMIT :max)""")
                .param("memberId", memberId)
                .param("max", MAX_DEVICES_PER_MEMBER)
                .update();
    }

    /** 이 회원의 토큰이면 지운다(로그아웃). 없거나 남의 토큰이면 그냥 넘어간다 */
    void remove(UUID memberId, String token) {
        jdbc.sql("DELETE FROM notification.device_tokens WHERE token = :token AND member_id = :memberId")
                .param("token", token)
                .param("memberId", memberId)
                .update();
    }

    /** FCM이 더는 없는 토큰이라고 답했다(앱 삭제 · 토큰 갱신). 다시 보내지 않게 지운다 */
    public void deleteById(UUID id) {
        jdbc.sql("DELETE FROM notification.device_tokens WHERE id = :id").param("id", id).update();
    }

    /** 회원 탈퇴 */
    public void deleteForMember(UUID memberId) {
        jdbc.sql("DELETE FROM notification.device_tokens WHERE member_id = :memberId").param("memberId", memberId).update();
    }

    /** PostgreSQL 드라이버는 Instant를 바로 받지 못해서 UTC 시각으로 바꿔 넘긴다 */
    private static OffsetDateTime timestamp(Instant instant) {
        return OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
