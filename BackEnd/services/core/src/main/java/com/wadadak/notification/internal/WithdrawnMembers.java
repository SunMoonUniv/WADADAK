package com.wadadak.notification.internal;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.UUID;

/**
 * 탈퇴 회원 표시. notification은 member를 호출하지 않으므로(개발 정책 4.3), 탈퇴 여부는 {@code MemberWithdrawnEvent}로 받아 둔다.
 *
 * <p>[왜 필요한가] 탈퇴해도 액세스 토큰은 만료(1시간)까지 살아 있고, 탈퇴 회원이 등록한 코스는 남아 만료 임박 이벤트가 계속 온다.
 * 이 표시가 있으면 토큰 등록 · 설정 · 알림 만들기를 모두 받지 않는다.
 *
 * <p>하위 패키지(device · setting)에서도 쓰므로 {@code public}이다. 모듈 밖에서는 Modulith가 막는다(internal).
 */
@Repository
@RequiredArgsConstructor
public class WithdrawnMembers {

    private final JdbcClient jdbc;

    /** 탈퇴 표시를 남긴다. 같은 이벤트가 다시 와도 한 줄이다 */
    void mark(UUID memberId, Instant withdrawnAt) {
        jdbc.sql("""
                        INSERT INTO notification.withdrawn_members (member_id, withdrawn_at, created_at, updated_at)
                        VALUES (:memberId, :withdrawnAt, now(), now())
                        ON CONFLICT (member_id) DO NOTHING""")
                .param("memberId", memberId)
                .param("withdrawnAt", OffsetDateTime.ofInstant(withdrawnAt, ZoneOffset.UTC))
                .update();
    }

    public boolean isWithdrawn(UUID memberId) {
        return jdbc.sql("SELECT EXISTS (SELECT 1 FROM notification.withdrawn_members WHERE member_id = :memberId)")
                .param("memberId", memberId)
                .query(Boolean.class)
                .single();
    }

    /** 토큰은 아직 살아 있지만 탈퇴한 회원이면 다시 로그인하게 한다(COMMON-002, member의 내 정보 API와 같다) */
    public void requireActive(UUID memberId) {
        if (isWithdrawn(memberId)) {
            throw new AppException(CommonErrorCode.UNAUTHORIZED);
        }
    }
}
