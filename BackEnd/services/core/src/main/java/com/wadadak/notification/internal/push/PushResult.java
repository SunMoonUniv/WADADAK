package com.wadadak.notification.internal.push;

/**
 * 푸시 하나를 보낸 결과. 발송 작업은 결과마다 다르게 처리한다.
 *
 * @param outcome 결과 종류
 * @param reason  실패 이유(발송 줄의 {@code last_error}에 남긴다). 보냈으면 null
 */
public record PushResult(Outcome outcome, String reason) {

    public enum Outcome {
        /** 보냈다 */
        SENT,
        /** 없어진 토큰이다(앱 삭제 · 토큰 갱신). 토큰을 지우고 다시 보내지 않는다 */
        INVALID_TOKEN,
        /** 잠깐의 문제다(FCM 점검 · 연결 실패 · 보내기 한도). 조금 뒤에 다시 보낸다 */
        RETRY_LATER,
        /** 다시 보내도 안 된다(잘못된 메시지). 토큰은 그대로 두고 이 줄만 실패로 끝낸다 */
        REJECTED
    }

    public static PushResult sent() {
        return new PushResult(Outcome.SENT, null);
    }

    public static PushResult invalidToken(String reason) {
        return new PushResult(Outcome.INVALID_TOKEN, reason);
    }

    public static PushResult retryLater(String reason) {
        return new PushResult(Outcome.RETRY_LATER, reason);
    }

    public static PushResult rejected(String reason) {
        return new PushResult(Outcome.REJECTED, reason);
    }
}
