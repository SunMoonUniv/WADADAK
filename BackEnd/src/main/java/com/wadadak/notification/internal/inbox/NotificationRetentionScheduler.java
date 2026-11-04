package com.wadadak.notification.internal.inbox;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Clock;

/**
 * 매일 04:00(Asia/Seoul) 30일 지난 알림을 지운다. 알림함은 최근 30일만 보이므로({@link NotificationInboxService#KEEP_FOR})
 * 그보다 오래된 알림은 쓸 곳이 없다. 서버를 여러 대로 늘려도 ShedLock으로 한 대에서만 돈다(개발 정책 8.1).
 *
 * <p>[04:00인 이유] 이용이 가장 적고, 만료 임박 알림(09:00)과 겹치지 않는다. 그 시각에 서버가 꺼져 있었으면 다음 날 지운다.
 * 목록 · 개수는 30일로 거르므로 하루 늦게 지워도 화면에는 보이지 않는다.
 */
@Slf4j
@Component
@RequiredArgsConstructor
class NotificationRetentionScheduler {

    private final NotificationInboxRepository repository;
    private final Clock clock;

    @Scheduled(cron = "0 0 4 * * *", zone = "Asia/Seoul")
    @SchedulerLock(name = "notification.retention", lockAtLeastFor = "PT1M")
    void deleteOld() {
        int deleted = repository.deleteCreatedBefore(clock.instant().minus(NotificationInboxService.KEEP_FOR));
        if (deleted > 0) {
            log.info("30일 지난 알림 {}개를 지웠다", deleted);
        }
    }
}
