package com.wadadak.common.outbox;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.modulith.events.core.EventPublicationRepository;
import org.springframework.modulith.events.core.TargetEventPublication;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.TimeUnit;

/**
 * 10분 이상 밀린 이벤트를 경고 로그로 알린다(개발 정책 5.5). 메신저 알림은 운영 단계에서 붙인다.
 */
@Slf4j
@Component
@RequiredArgsConstructor
class EventMonitor {

    private static final Duration STALE_AFTER = Duration.ofMinutes(10);

    private final EventPublicationRepository eventPublicationRepository;
    private final Clock clock;

    @Scheduled(fixedDelay = 1, timeUnit = TimeUnit.MINUTES)
    @SchedulerLock(name = "common.event-monitor")
    void warnStale() {
        List<TargetEventPublication> stale = eventPublicationRepository
                .findIncompletePublicationsPublishedBefore(clock.instant().minus(STALE_AFTER));
        for (TargetEventPublication publication : stale) {
            log.warn("이벤트 처리 지연: publicationId={}, listener={}, eventType={}, publishedAt={}",
                    publication.getIdentifier(), publication.getTargetIdentifier().getValue(),
                    publication.getEvent().getClass().getSimpleName(), publication.getPublicationDate());
        }
    }
}
