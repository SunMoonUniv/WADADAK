package com.wadadak.member.internal.account;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.event.member.MemberRegionChangedEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * ranking이 회원 지역 이력을 받기 전에 가입한 회원의 활동 지역을 다시 보낸다. 대상은 마이그레이션이 {@code member.region_event_backfill}에 넣었다.
 * 가입 때 지역으로 보낸다(이전 지역 없음, 시각은 가입 시각). ranking은 가입한 주부터 그 지역에 넣는다.
 * 받는 쪽이 (회원, 버전)으로 한 번만 저장하므로 인스턴스 여러 대가 같이 돌아도 된다.
 */
@Component
@RequiredArgsConstructor
class RegionEventBackfill {

    private final JdbcClient jdbc;
    private final MemberRepository memberRepository;
    private final ApplicationEventPublisher events;

    @EventListener(ApplicationReadyEvent.class)
    @Transactional
    public void republish() {
        List<UUID> ids = jdbc.sql("SELECT member_id FROM member.region_event_backfill FOR UPDATE SKIP LOCKED")
                .query(UUID.class)
                .list();
        if (ids.isEmpty()) {
            return;
        }
        memberRepository.findAllById(ids).stream()
                .filter(member -> !member.isWithdrawn())
                .forEach(member -> events.publishEvent(new MemberRegionChangedEvent(UuidV7.create(), member.getCreatedAt(),
                        member.getId(), member.getRegionCode(), null, member.getVersion())));
        jdbc.sql("DELETE FROM member.region_event_backfill WHERE member_id IN (:ids)")
                .param("ids", ids)
                .update();
    }
}
