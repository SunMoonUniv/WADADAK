package com.wadadak.run.internal.recording;

import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
class RunProcessingWorker {
    private static final Logger log=LoggerFactory.getLogger(RunProcessingWorker.class);
    private final RunService runs;
    private final GpsGapWorker gpsGaps;
    RunProcessingWorker(RunService runs, GpsGapWorker gpsGaps) { this.runs=runs; this.gpsGaps=gpsGaps; }
    @Scheduled(fixedDelay=2000)
    @SchedulerLock(name="freeRunProcessing",lockAtMostFor="PT2M")
    void process() {
        for(var id:runs.waiting()) {
            try { runs.process(id); }
            catch(RuntimeException e) { log.error("Free run processing failed for {}",id,e); continue; }
            // 처리 트랜잭션이 끝난 뒤 바로 끊긴 구간 판단을 채운다(실패하면 1분 뒤 다시)
            try { gpsGaps.check(id); }
            catch(RuntimeException e) { log.error("GPS gap check failed for {}",id,e); }
        }
        for (var id:runs.unpublished()) {
            try { runs.publishStored(id); }
            catch(RuntimeException e) { log.error("Run event publication failed for {}",id,e); }
        }
    }
}
