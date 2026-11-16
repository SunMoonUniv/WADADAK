package com.wadadak.run.internal.recording;

import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
class GpsSourceLinkWorker {
    private final GpsSourceLinkService links;
    GpsSourceLinkWorker(GpsSourceLinkService links) {this.links=links;}
    @Scheduled(fixedDelay=60000,initialDelay=60000)
    @SchedulerLock(name="run.gps-source-link",lockAtMostFor="PT5M")
    public void run() {for(var id:links.pending()) links.process(id);}
}
