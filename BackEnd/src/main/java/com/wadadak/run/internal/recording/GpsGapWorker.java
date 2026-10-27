package com.wadadak.run.internal.recording;

import com.wadadak.course.CourseApi;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;

/**
 * 기록마다 GPS 코스 등록 끊긴 구간 판단(CourseApi.checkGpsGaps, F7)을 채운다. 판단은 쓰기 트랜잭션 밖에서 한다(개발 정책 4.4):
 * 경로 읽기(읽기 트랜잭션) → 판단 → 저장(쓰기 트랜잭션).
 * 새 기록은 처리 직후 {@link #check}로, 판단 도입 전 기록과 기준 버전이 바뀐 기록은 1분마다 {@link #backfill}로.
 */
@Component
class GpsGapWorker {

    private static final Logger log = LoggerFactory.getLogger(GpsGapWorker.class);
    private final RunService runs;
    private final CourseApi courses;

    GpsGapWorker(RunService runs, CourseApi courses) {
        this.runs = runs;
        this.courses = courses;
    }

    void check(UUID id) {
        var segments = runs.gpsGapSegments(id);
        if (segments != null) {
            runs.saveGpsGap(id, courses.checkGpsGaps(segments));
        }
    }

    @Scheduled(fixedDelay = 60_000)
    @SchedulerLock(name = "gpsGapBackfill", lockAtMostFor = "PT5M")
    void backfill() {
        // 지금 기준 버전은 공개 상수가 없어 빈 경로 판단으로 알아낸다(계산만 한다)
        String version = courses.checkGpsGaps(List.of()).version();
        for (var id : runs.gpsGapOutdated(version)) {
            try {
                check(id);
            } catch (RuntimeException e) {
                log.error("GPS gap check failed for {}", id, e);
            }
        }
    }
}
