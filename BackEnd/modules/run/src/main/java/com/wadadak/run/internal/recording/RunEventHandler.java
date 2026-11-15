package com.wadadak.run.internal.recording;

import com.wadadak.event.member.MemberWithdrawnEvent;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

@Component
class RunEventHandler {
    private final RunService runs;
    private final PublicGhostAccess publicGhosts;
    private final GpsSourceLinkService links;
    RunEventHandler(RunService runs, PublicGhostAccess publicGhosts, GpsSourceLinkService links) {
        this.runs = runs; this.publicGhosts=publicGhosts; this.links=links;
    }
    @ApplicationModuleListener
    public void on(com.wadadak.event.course.GpsCourseRegisteredEvent event) { links.receive(event); }
    @ApplicationModuleListener
    public void on(com.wadadak.event.course.CourseStatusChangedEvent event) { links.courseStatus(event); }
    @ApplicationModuleListener
    public void on(com.wadadak.event.member.MemberVisibilityChangedEvent event) { publicGhosts.visibility(event); }
    @ApplicationModuleListener
    public void on(MemberWithdrawnEvent event) {
        runs.withdraw(event.memberId(), event.withdrawnAt());
        publicGhosts.forget(event.memberId());
    }
}
