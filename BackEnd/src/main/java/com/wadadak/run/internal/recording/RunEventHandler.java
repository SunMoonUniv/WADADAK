package com.wadadak.run.internal.recording;

import com.wadadak.event.member.MemberWithdrawnEvent;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

@Component
class RunEventHandler {
    private final RunService runs;
    private final PublicGhostAccess publicGhosts;
    RunEventHandler(RunService runs, PublicGhostAccess publicGhosts) { this.runs = runs; this.publicGhosts=publicGhosts; }
    @ApplicationModuleListener
    public void on(com.wadadak.event.member.MemberVisibilityChangedEvent event) { publicGhosts.visibility(event); }
    @ApplicationModuleListener
    public void on(MemberWithdrawnEvent event) {
        runs.withdraw(event.memberId(), event.withdrawnAt());
        publicGhosts.forget(event.memberId());
    }
}
