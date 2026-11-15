package com.wadadak.notification.internal.inbox;

/**
 * 안 읽은 알림 수(최근 30일). A2 종 아이콘의 빨간 점 · F3 `읽지 않음 N`.
 *
 * @param count 안 읽은 알림 수
 */
record UnreadCount(long count) {
}
