package com.wadadak.notification.internal.device;

import com.wadadak.notification.internal.WithdrawnMembers;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.UUID;

/** 기기 토큰 등록 · 삭제. 로그인한 본인의 기기만 다룬다 */
@Service
@RequiredArgsConstructor
class DeviceTokenService {

    private final DeviceTokenRepository tokens;
    private final WithdrawnMembers withdrawnMembers;
    private final Clock clock;

    /** 예전 계정 줄 지우기 · 등록 · 오래된 기기 정리를 한 트랜잭션으로 묶는다. 중간에 실패하면 모두 취소된다 */
    @Transactional
    void register(UUID memberId, RegisterTokenRequest request) {
        withdrawnMembers.requireActive(memberId);
        tokens.register(memberId, request.token(), request.platform(), clock.instant());
    }

    /** 탈퇴한 회원의 토큰은 이미 지워졌으므로 확인 없이 지운다 */
    @Transactional
    void remove(UUID memberId, RemoveTokenRequest request) {
        tokens.remove(memberId, request.token());
    }
}
