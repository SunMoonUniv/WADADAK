package com.wadadak.run.internal.recording;

import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** 구간 종료 신호도 업로드도 없는 코스 러닝(앱 강제 종료·방치)을 현재 러너 수에서 뺀다(정책 D-14) */
@Component
class CourseRunReleaseWorker {

    private static final Logger log = LoggerFactory.getLogger(CourseRunReleaseWorker.class);
    private final CourseRunService courseRuns;

    CourseRunReleaseWorker(CourseRunService courseRuns) {
        this.courseRuns = courseRuns;
    }

    @Scheduled(fixedDelay = 60_000)
    @SchedulerLock(name = "courseRunRelease", lockAtMostFor = "PT2M")
    void releaseExpired() {
        for (var id : courseRuns.expiredIds()) {
            try {
                courseRuns.releaseExpired(id);
            } catch (RuntimeException e) {
                log.error("Course run release failed for {}", id, e);
            }
        }
    }
}
