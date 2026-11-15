package com.wadadak.notification.internal.inbox;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * 알림함의 알림 한 줄(Figma F3 알림 센터).
 *
 * @param id        알림 ID. 읽음으로 바꿀 때 쓴다
 * @param kind      알림 종류. 지금은 {@code COURSE_EXPIRING_SOON}뿐이다
 * @param title     제목(예: `내 코스 만료 임박`)
 * @param body      본문(예: `‘한강 야경’ 코스가 7일 뒤 만료돼요.`)
 * @param data      누르면 열 화면 정보. 푸시의 data와 같다(만료 임박은 {@code type} · {@code courseId} → B1)
 * @param createdAt 알림을 만든 시각. 앱이 `12분 전`처럼 보인다
 * @param read      읽었는가. false면 파란 점을 보인다
 */
record NotificationItem(UUID id, String kind, String title, String body, Map<String, String> data, Instant createdAt,
                        boolean read) {
}
