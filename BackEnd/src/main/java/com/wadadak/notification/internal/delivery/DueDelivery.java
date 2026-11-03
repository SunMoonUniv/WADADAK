package com.wadadak.notification.internal.delivery;

import com.wadadak.notification.internal.push.PushMessage;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * 지금 보낼 차례인 발송 줄 하나(알림 × 기기).
 *
 * @param sameMember 토큰이 아직 이 알림을 받을 회원의 것인가. 그 사이 기기에 다른 계정이 로그인했으면 false다
 */
record DueDelivery(UUID notificationId, UUID deviceTokenId, String token, boolean sameMember, int attempts,
                   String title, String body, Map<String, String> data, Instant sendUntil) {

    PushMessage message() {
        return new PushMessage(title, body, data);
    }
}
