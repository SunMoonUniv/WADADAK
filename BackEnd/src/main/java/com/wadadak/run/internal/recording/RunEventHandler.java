package com.wadadak.run.internal.recording;

import com.wadadak.event.member.MemberWithdrawnEvent;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

@Component
class RunEventHandler {
    private final RunService runs;
    RunEventHandler(RunService runs) { this.runs = runs; }
    @ApplicationModuleListener
    public void on(MemberWithdrawnEvent event) {
        runs.withdraw(event.memberId(), event.withdrawnAt());
    }
}
