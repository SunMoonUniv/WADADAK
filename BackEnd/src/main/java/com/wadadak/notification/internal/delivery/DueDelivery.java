package com.wadadak.notification.internal.delivery;

import com.wadadak.notification.internal.push.PushMessage;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * 지금 보낼 차례인 발송 줄 하나(알림 × 기기).
 *
 * @param sameMember 토큰이 아직 이 알림을 받을 회원의 것인가. 그 사이 기기에 다른 계정이 로그인했으면 false다
 */
record DueDelivery(UUID notificationId, UUID deviceTokenId, String token, boolean sameMember, int attempts,
                   String title, String body, Map<String, String> data, Instant sendUntil) {

    /**
     * 보낼 메시지. data에 알림 ID({@code notificationId})를 붙인다. 앱이 푸시를 눌러 열면 이 ID로 알림함의 그 알림을 읽음으로 바꾼다.
     * 저장한 data에는 넣지 않는다(알림함 목록은 id를 따로 준다).
     */
    PushMessage message() {
        Map<String, String> withId = new HashMap<>(data);
        withId.put("notificationId", notificationId.toString());
        return new PushMessage(title, body, Map.copyOf(withId));
    }
}
