package com.wadadak.event.member;

import com.wadadak.event.IntegrationEvent;

import java.time.Instant;
import java.util.UUID;

/**
 * 회원 활동 지역 설정(상태형). 키: memberId. 수신 측은 저장된 version보다 큰 값만 반영한다.
 * 가입할 때와 프로필에서 활동 지역을 바꿀 때 발행한다.
 * ranking은 가입 때 지역은 바로, 바꾼 지역은 {@code occurredAt} 다음 주(월요일 00:00, Asia/Seoul)부터 지역 주간 랭킹에 반영한다(정책 공통 6).
 *
 * @param regionCode         활동 지역(시·군·구) 법정동 코드
 * @param previousRegionCode 바꾸기 전 활동 지역. 가입할 때는 {@code null}
 * @param version            회원 엔티티의 {@code @Version}
 */
public record MemberRegionChangedEvent(UUID eventId, Instant occurredAt, UUID memberId, String regionCode,
                                       String previousRegionCode, long version) implements IntegrationEvent {
}
