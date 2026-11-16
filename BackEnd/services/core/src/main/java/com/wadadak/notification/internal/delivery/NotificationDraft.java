package com.wadadak.notification.internal.delivery;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * 만들 알림 한 건. 이벤트를 받은 쪽이 이것을 만들어 {@link NotificationStore#enqueue}에 넘긴다.
 *
 * @param memberId  받는 회원
 * @param kind      알림 종류
 * @param dedupeKey 같은 일이면 같은 값. 이 값이 같은 알림은 한 번만 만든다(이벤트가 다시 와도)
 * @param title     제목
 * @param body      본문
 * @param data      앱이 누를 때 쓸 값(FCM data). {@code type}에 종류를 넣는다
 * @param sendUntil 이 시각까지 못 보내면 보내지 않는다
 */
public record NotificationDraft(UUID memberId, NotificationKind kind, String dedupeKey, String title, String body,
                                Map<String, String> data, Instant sendUntil) {
}
