package com.wadadak.member.internal.auth;

import com.wadadak.event.member.MemberWithdrawnEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * 탈퇴하면 그 회원의 리프레시 토큰을 모두 지운다(개발 정책 6.2, 모든 기기 로그아웃).
 *
 * <p>[왜 이벤트로] 토큰은 auth 패키지 안에 숨겨 둔 것이라 탈퇴를 처리하는 account 패키지가 직접 만지지 않는다.
 * {@code @EventListener}는 다른 모듈용 {@code @ApplicationModuleListener}와 달리 발행한 그 자리에서 같은 트랜잭션으로 바로 실행된다.
 * 그래서 탈퇴 저장과 토큰 삭제가 함께 성공하거나 함께 실패한다.
 * 토큰이 남는 일이 생겨도 갱신(refresh)이 탈퇴 회원을 막는다.
 */
@Component
@RequiredArgsConstructor
class WithdrawnTokenCleaner {

    private final RefreshTokenRepository refreshTokenRepository;

    @EventListener
    void on(MemberWithdrawnEvent event) {
        refreshTokenRepository.deleteByMemberId(event.memberId());
    }
}
