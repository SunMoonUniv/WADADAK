package com.wadadak.run.internal.recording;

import com.wadadak.course.GpsGapRule;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * 기록마다 GPS 코스 등록 끊긴 구간 판단(GpsGapRule.check, F7)을 채운다. 판단은 쓰기 트랜잭션 밖에서 한다:
 * 경로 읽기(읽기 트랜잭션) → 판단 → 저장(쓰기 트랜잭션).
 * 새 기록은 처리 직후 {@link #check}로, 판단 도입 전 기록과 기준 버전이 바뀐 기록은 1분마다 {@link #backfill}로.
 */
@Component
class GpsGapWorker {

    private static final Logger log = LoggerFactory.getLogger(GpsGapWorker.class);
    private final RunService runs;

    GpsGapWorker(RunService runs) {
        this.runs = runs;
    }

    void check(UUID id) {
        var segments = runs.gpsGapSegments(id);
        if (segments != null) {
            runs.saveGpsGap(id, GpsGapRule.check(segments));
        }
    }

    @Scheduled(fixedDelay = 60_000)
    @SchedulerLock(name = "gpsGapBackfill", lockAtMostFor = "PT5M")
    void backfill() {
        for (var id : runs.gpsGapOutdated(GpsGapRule.VERSION)) {
            try {
                check(id);
            } catch (RuntimeException e) {
                log.error("GPS gap check failed for {}", id, e);
            }
        }
    }
}
