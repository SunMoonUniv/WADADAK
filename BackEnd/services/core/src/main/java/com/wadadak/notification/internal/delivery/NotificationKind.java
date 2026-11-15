package com.wadadak.notification.internal.delivery;

/**
 * 알림 종류. {@code notifications.kind}에 이름으로 저장하고, 앱에는 FCM data의 {@code type}으로 보낸다.
 * 늘리면 새 마이그레이션으로 CHECK도 함께 늘린다. 랭킹 알림(기록 경신 · 순위 변동)은 고도화 범위다(정책 문서 고도화 목록).
 */
public enum NotificationKind {
    /** 내 코스 만료 임박(D-7 · D-1). 누르면 B1 코스 상세 */
    COURSE_EXPIRING_SOON
}
