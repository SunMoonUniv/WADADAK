package com.wadadak.common.outbox;

import lombok.RequiredArgsConstructor;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.modulith.events.IncompleteEventPublications;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

/**
 * 1분마다 5분 이상 미완료된 이벤트를 재전송한다(개발 정책 5.5).
 * Modulith 2.1은 재전송 API만 있고 주기 실행은 없어 직접 스케줄한다.
 */
@Component
@RequiredArgsConstructor
class EventRetryScheduler {

    private final IncompleteEventPublications incompleteEventPublications;

    @Scheduled(fixedDelay = 1, timeUnit = TimeUnit.MINUTES)
    @SchedulerLock(name = "common.event-retry")
    void resubmit() {
        incompleteEventPublications.resubmitIncompletePublicationsOlderThan(Duration.ofMinutes(5));
    }
}
