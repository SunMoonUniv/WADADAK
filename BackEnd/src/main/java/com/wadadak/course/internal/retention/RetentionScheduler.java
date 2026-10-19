package com.wadadak.course.internal.retention;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.course.internal.course.CourseRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.domain.Limit;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;
import java.util.function.Predicate;

/**
 * 만료 배치(F11, 정책 공통 4). ShedLock으로 한 인스턴스에서만 돈다(개발 정책 8.1).
 * 테스트는 {@code app.course.retention-batch.enabled: false}로 끄고 메서드를 직접 부른다.
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "app.course.retention-batch.enabled", havingValue = "true", matchIfMissing = true)
class RetentionScheduler {

    /** 만료 임박 알림을 보내는 남은 날(정책 공통 4) */
    static final List<Integer> NOTICE_DAYS = List.of(7, 1);

    private static final int PAGE_SIZE = 100;

    private final CourseRepository courseRepository;
    private final RetentionService retention;
    private final Clock clock;

    /**
     * 1분마다 만료된 코스를 비공개로, 숨긴 지 24시간 지난 코스를 삭제로 바꾼다.
     * 만료 시각(23:59:59)이 지나고 이 배치가 돌 때까지 최대 1분은 공개로 남는다.
     */
    @Scheduled(initialDelay = 1, fixedDelay = 1, timeUnit = TimeUnit.MINUTES)
    @SchedulerLock(name = "course.retention")
    void hideAndDelete() {
        int hidden = forEachPage(before -> courseRepository.findExpiredIds(before, Limit.of(PAGE_SIZE)),
                clock.instant().minusSeconds(1), retention::hideIfExpired);
        int deleted = forEachPage(before -> courseRepository.findHiddenIds(before, Limit.of(PAGE_SIZE)),
                clock.instant().minus(RetentionService.DELETE_AFTER), retention::deleteIfDue);
        if (hidden + deleted > 0) {
            log.info("만료 배치 비공개 {}개 · 삭제 {}개", hidden, deleted);
        }
    }

    /** 매일 09:00(Asia/Seoul) 만료일까지 7일 · 1일 남은 코스를 알린다. 그 시각에 서버가 꺼져 있었으면 그날은 보내지 않는다 */
    @Scheduled(cron = "0 0 9 * * *", zone = "Asia/Seoul")
    @SchedulerLock(name = "course.expiring-soon", lockAtLeastFor = "PT1M")
    void noticeExpiringSoon() {
        LocalDate today = LocalDate.now(clock.withZone(TimeConfig.SEOUL));
        for (int daysLeft : NOTICE_DAYS) {
            int count = retention.publishExpiringSoon(today, daysLeft);
            log.info("만료 임박 D-{} {}개", daysLeft, count);
        }
    }

    /** 한 쪽씩 받아 바꾼다. 쪽이 가득 찼고 하나라도 바꿨으면 다음 쪽을 받는다(바꾸지 못한 코스만 남아 같은 쪽을 계속 받지 않게) */
    private static <T> int forEachPage(Function<T, List<UUID>> page, T before, Predicate<UUID> change) {
        int total = 0;
        List<UUID> ids;
        int changed;
        do {
            ids = page.apply(before);
            changed = (int) ids.stream().filter(change).count();
            total += changed;
        } while (ids.size() == PAGE_SIZE && changed > 0);
        return total;
    }
}
