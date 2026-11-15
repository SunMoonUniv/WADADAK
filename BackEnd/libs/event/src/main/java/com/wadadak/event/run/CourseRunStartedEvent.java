package com.wadadak.event.run;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 코스 러닝 시작(증감형). 키: courseId. 카운트다운이 끝나 측정을 시작한 코스 도전마다 한 번 발행한다(정책 RUN-04).
 * 카운트다운 취소는 발행하지 않고, 같은 세션의 시작 재시도도 한 번만 발행한다.
 * course는 도전 수를 +1 하고 일별 통계는 {@code occurredAt}의 날짜(Asia/Seoul)에 반영한다(개발 정책 5.6).
 * 이 세션 기록을 지우면 {@link RunRecordDeletedEvent#startedAt()}에 이 이벤트의 {@code occurredAt}을 담아 같은 날짜에서 뺀다.
 * 발행은 코스 세션 시작(F6 B단계)에서 붙인다.
 */
public record CourseRunStartedEvent(UUID eventId, Instant occurredAt, UUID runSessionId, UUID courseId, UUID memberId)
        implements IntegrationEvent {
}
