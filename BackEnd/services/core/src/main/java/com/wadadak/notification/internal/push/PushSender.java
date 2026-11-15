package com.wadadak.notification.internal.push;

/**
 * 푸시 보내기(개발 정책 2장 `PushSender`). 외부 서비스(FCM)는 이 인터페이스 뒤에 숨긴다(개발 정책 10.2).
 *
 * <p>[왜 인터페이스인가] 발송 작업은 "보냈다 · 없는 토큰 · 나중에 다시"만 알면 된다. FCM 주소 · 인증 · 오류 형식은
 * {@link FcmPushSender}만 안다. 비밀키가 없는 로컬과 시험에서는 {@link LoggingPushSender}가 같은 자리에 들어간다
 * ({@link PushConfig}가 고른다). 나중에 알림 서비스를 떼어내도 이 경계는 그대로다.
 *
 * <p>예외를 던지지 않고 결과로 돌려준다. 어떤 실패든 발송 작업이 다음 줄을 계속 보낼 수 있어야 한다.
 */
public interface PushSender {

    PushResult send(String token, PushMessage message);
}
