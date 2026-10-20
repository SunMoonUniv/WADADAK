package com.wadadak.event.run;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 코스의 현재 러너 수(상태형). 키: courseId. 수신 측은 저장된 version보다 큰 값만 반영한다.
 * 코스 러닝 시작·구간 종료 신호·기록 업로드·자동 제외(정책 D-14)로 수가 바뀔 때 발행한다. 일시정지 중인 러너도 센다.
 * course는 현재 러너 수 복사본을 갱신해 실시간순 정렬과 목록·상세의 현재 러너 표시에 쓴다(개발 정책 5.6).
 * 발행은 코스 세션 시작·구간 종료(F6 B단계)에서 붙인다.
 *
 * @param activeCount 지금 그 코스를 달리는 세션 수(0 이상)
 * @param version     코스별로 커지는 값
 */
public record CourseActiveRunnersChangedEvent(UUID eventId, Instant occurredAt, UUID courseId, int activeCount,
                                              long version)
        implements IntegrationEvent {
}
