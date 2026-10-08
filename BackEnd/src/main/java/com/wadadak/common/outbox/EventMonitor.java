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
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

/**
 * 10분 이상 밀린 이벤트를 경고 로그로 알린다(개발 정책 5.5). 메신저 알림은 운영 단계에서 붙인다.
 * 밀린 건이 많아도 한 줄로 요약한다. 이벤트 본문은 읽지 않는다(삭제된 이벤트 타입이어도 감시가 멈추지 않게).
 */
@Slf4j
@Component
@RequiredArgsConstructor
class EventMonitor {

    private static final Duration STALE_AFTER = Duration.ofMinutes(10);

    private final EventPublicationRepository eventPublicationRepository;
    private final Clock clock;

    @Scheduled(fixedDelay = 1, timeUnit = TimeUnit.MINUTES)
    @SchedulerLock(name = "common.event-monitor", lockAtLeastFor = "PT30S")
    void warnStale() {
        List<TargetEventPublication> stale = eventPublicationRepository
                .findIncompletePublicationsPublishedBefore(clock.instant().minus(STALE_AFTER));
        if (stale.isEmpty()) {
            return;
        }
        Instant oldest = stale.stream().map(TargetEventPublication::getPublicationDate)
                .min(Comparator.naturalOrder()).orElseThrow();
        Set<String> listeners = stale.stream().map(publication -> publication.getTargetIdentifier().getValue())
                .collect(Collectors.toCollection(TreeSet::new));
        log.warn("이벤트 처리 지연 {}건, 가장 오래된 발행 {}, 리스너 {}", stale.size(), oldest, listeners);
    }
}
