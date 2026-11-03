package com.wadadak.notification.internal.push;

import java.util.Map;

/**
 * 기기 하나에 보낼 푸시 한 개.
 *
 * @param title 알림 제목(잠금 화면 · 알림 창에 보인다)
 * @param body  알림 본문
 * @param data  앱이 알림을 눌렀을 때 쓸 값. FCM data는 값이 모두 문자열이어야 한다
 */
public record PushMessage(String title, String body, Map<String, String> data) {
}
