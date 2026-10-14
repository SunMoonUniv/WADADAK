package com.wadadak.run.internal;

import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
class RunProcessingWorker {
    private static final Logger log=LoggerFactory.getLogger(RunProcessingWorker.class);
    private final RunService runs;
    RunProcessingWorker(RunService runs) { this.runs=runs; }
    @Scheduled(fixedDelay=2000)
    @SchedulerLock(name="freeRunProcessing",lockAtMostFor="PT2M")
    void process() {
        for(var id:runs.waiting()) {
            try { runs.process(id); }
            catch(RuntimeException e) { log.error("Free run processing failed for {}",id,e); }
        }
    }
}
