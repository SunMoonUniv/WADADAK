package com.wadadak.course.internal.registration;

import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Enable deliberately after reviewing legacy source relations; no automatic production backfill on deployment. */
@Component
@ConditionalOnProperty(name="app.course.gps-source-backfill.enabled",havingValue="true")
class GpsSourceBackfillWorker {
    private final GpsSourcePublicationService publications;
    GpsSourceBackfillWorker(GpsSourcePublicationService publications) {this.publications=publications;}
    @Scheduled(fixedDelay=60000,initialDelay=60000)
    @SchedulerLock(name="course.gps-source-backfill",lockAtMostFor="PT5M")
    public void run() { for(var id:publications.pending()) publications.publish(id); }
}
