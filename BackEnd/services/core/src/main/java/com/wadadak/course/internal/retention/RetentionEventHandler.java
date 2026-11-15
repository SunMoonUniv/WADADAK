package com.wadadak.course.internal.retention;

import com.wadadak.event.run.RunSessionEndedEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
class RetentionEventHandler {

    private final RetentionService retention;

    /**
     * 서버가 확정한 완주로 유지 기간을 연장한다(정책 공통 4). 자유 러닝 · 미완주는 연장하지 않는다.
     * 같은 이벤트가 다시 오거나 순서가 바뀌어 와도 고정 구간마다 한 번만 연장된다({@code Course#extendByCompletion}).
     */
    @ApplicationModuleListener
    public void on(RunSessionEndedEvent event) {
        if (event.courseId() == null || !event.completed()) {
            return;
        }
        retention.extend(event.courseId(), event.registeredAt());
    }
}
