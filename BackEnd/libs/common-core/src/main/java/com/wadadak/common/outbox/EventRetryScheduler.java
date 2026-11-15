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
 * {@code lockAtLeastFor}: 인스턴스가 여러 대여도 1분에 한 번만 돈다(락이 바로 풀리면 다른 인스턴스가 이어서 또 실행한다).
 */
@Component
@RequiredArgsConstructor
class EventRetryScheduler {

    private final IncompleteEventPublications incompleteEventPublications;

    @Scheduled(fixedDelay = 1, timeUnit = TimeUnit.MINUTES)
    @SchedulerLock(name = "common.event-retry", lockAtLeastFor = "PT30S")
    void resubmit() {
        incompleteEventPublications.resubmitIncompletePublicationsOlderThan(Duration.ofMinutes(5));
    }
}
