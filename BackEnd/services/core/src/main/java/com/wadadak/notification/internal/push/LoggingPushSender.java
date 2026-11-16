package com.wadadak.notification.internal.push;

import lombok.extern.slf4j.Slf4j;

/**
 * FCM 비밀키가 없을 때(로컬 · 시험) 쓰는 가짜 발송. 실제로 보내지 않고 로그만 남기고, 늘 보냈다고 답한다.
 * 그래서 키 없이도 알림 만들기 → 발송 → 기록까지 전체 흐름을 로컬에서 돌려 볼 수 있다(개발 정책 10.2).
 */
@Slf4j
class LoggingPushSender implements PushSender {

    @Override
    public PushResult send(String token, PushMessage message) {
        // 토큰은 기기를 가리키는 값이라 앞부분만 남긴다
        log.info("[푸시 · 로컬] {}… {} / {} {}", token.substring(0, Math.min(10, token.length())),
                message.title(), message.body(), message.data());
        return PushResult.sent();
    }
}
