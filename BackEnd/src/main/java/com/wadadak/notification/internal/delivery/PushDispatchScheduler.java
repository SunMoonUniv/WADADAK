package com.wadadak.notification.internal.delivery;

import lombok.RequiredArgsConstructor;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

/**
 * 10초마다 푸시를 보낸다. 서버를 여러 대로 늘려도 ShedLock으로 한 대에서만 돈다(개발 정책 8.1).
 * 만료 임박은 하루 한 번 오전 9시에 몰려 오므로, 10초 늦게 가는 것은 문제가 아니다.
 * 시험은 {@code app.notification.dispatch.enabled: false}로 끄고 {@link PushDispatcher#dispatchDue}를 직접 부른다.
 */
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "app.notification.dispatch.enabled", havingValue = "true", matchIfMissing = true)
class PushDispatchScheduler {

    /**
     * 한 차례에 이어 보내는 시간. 잠금(ShedLock 기본 10분)보다 한참 짧게 둔다. 잠금이 먼저 풀리면 다른 인스턴스가
     * 같은 줄을 또 보낼 수 있다. 묶음 하나는 FCM이 느려도 7분 안에 끝난다({@link PushDispatcher#BATCH_SIZE})
     */
    private static final Duration KEEP_GOING_FOR = Duration.ofMinutes(1);

    private final PushDispatcher dispatcher;

    @Scheduled(initialDelay = 10, fixedDelay = 10, timeUnit = TimeUnit.SECONDS)
    @SchedulerLock(name = "notification.push-dispatch")
    void dispatch() {
        long deadline = System.nanoTime() + KEEP_GOING_FOR.toNanos();
        // 한 묶음을 꽉 채워 처리했으면 남은 줄이 있을 수 있어 10초 기다리지 않고 바로 다음 묶음을 본다
        while (dispatcher.dispatchDue() == PushDispatcher.BATCH_SIZE && System.nanoTime() < deadline) {
            // 다음 묶음
        }
    }
}
