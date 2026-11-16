package com.wadadak.notification.internal.delivery;

import com.wadadak.notification.internal.device.DeviceTokenRepository;
import com.wadadak.notification.internal.push.PushResult;
import com.wadadak.notification.internal.push.PushSender;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;

/**
 * 차례가 된 발송 줄을 보내고 결과를 적는다. {@link PushDispatchScheduler}가 10초마다 부른다(시험은 직접 부른다).
 *
 * <p>[트랜잭션을 쓰지 않는 이유] 보내기는 네트워크라 몇 초 걸릴 수 있다. 그동안 DB 연결과 잠금을 붙잡지 않게
 * 줄마다 결과 UPDATE 한 번으로 끝낸다(개발 정책 4.4와 같은 생각). 한 번에 한 인스턴스만 돌아서(ShedLock) 같은 줄을
 * 두 곳에서 보내지 않는다.
 */
@Slf4j
@Component
@RequiredArgsConstructor
class PushDispatcher {

    /** 한 번에 보낼 줄 수. FCM이 멈춰 모두 시간 초과(약 8초)여도 ShedLock 기본 잠금(10분) 안에 끝난다 */
    static final int BATCH_SIZE = 50;

    /** 잠깐의 실패가 이만큼 이어지면 FCM이 멈춘 것으로 보고 이번 차례를 멈춘다. 남은 줄은 다음 차례에 보낸다 */
    static final int STOP_AFTER_RETRIES = 3;

    private static final Duration MAX_BACKOFF = Duration.ofMinutes(30);

    private final NotificationStore store;
    private final DeviceTokenRepository tokens;
    private final PushSender sender;
    private final Clock clock;

    /** 보낼 줄을 한 번 훑는다. 처리한 줄 수를 돌려준다 */
    int dispatchDue() {
        List<DueDelivery> due = store.due(clock.instant(), BATCH_SIZE);
        int handled = 0;
        int retriesInARow = 0;
        for (DueDelivery delivery : due) {
            Instant now = clock.instant();
            handled++;
            // 기한이 지났거나, 그 사이 기기에 다른 계정이 로그인했다. 예전 계정의 알림을 새 주인에게 보내지 않는다
            if (!delivery.sameMember() || !now.isBefore(delivery.sendUntil())) {
                store.markExpired(delivery, now);
                continue;
            }
            PushResult result = send(delivery);
            switch (result.outcome()) {
                case SENT -> {
                    store.markSent(delivery, clock.instant());
                    retriesInARow = 0;
                }
                case INVALID_TOKEN -> {
                    // 토큰을 지우면 이 기기에 보낼 다른 줄도 함께 지워진다(ON DELETE CASCADE)
                    tokens.deleteById(delivery.deviceTokenId());
                    retriesInARow = 0;
                }
                case REJECTED -> {
                    log.warn("푸시 실패(다시 보내지 않음) · 알림 {} · {}", delivery.notificationId(), result.reason());
                    store.markFailed(delivery, result.reason(), clock.instant());
                    retriesInARow = 0;
                }
                case RETRY_LATER -> {
                    store.retryLater(delivery, now.plus(backoff(delivery.attempts() + 1)), result.reason(), clock.instant());
                    if (++retriesInARow >= STOP_AFTER_RETRIES) {
                        log.warn("푸시 실패가 이어져 이번 차례를 멈춘다 · {}", result.reason());
                        return handled;
                    }
                }
            }
        }
        return handled;
    }

    /** {@link PushSender}는 예외를 던지지 않기로 했지만, 혹시 던져도 다른 줄은 계속 보낸다 */
    private PushResult send(DueDelivery delivery) {
        try {
            return sender.send(delivery.token(), delivery.message());
        } catch (RuntimeException e) {
            return PushResult.retryLater(e.getClass().getSimpleName() + ": " + e.getMessage());
        }
    }

    /** n번째 실패 뒤 기다릴 시간: 1분 · 2분 · 4분 · 8분 · 16분 · 30분 · 30분 … 보낼 기한이 지나면 그만둔다 */
    static Duration backoff(int attempts) {
        Duration wait = Duration.ofMinutes(1L << Math.min(attempts - 1, 5));
        return wait.compareTo(MAX_BACKOFF) > 0 ? MAX_BACKOFF : wait;
    }
}
