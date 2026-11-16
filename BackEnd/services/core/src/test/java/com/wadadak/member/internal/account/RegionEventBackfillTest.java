package com.wadadak.member.internal.account;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.event.member.MemberRegionChangedEvent;
import com.wadadak.member.internal.social.SocialAccount;
import com.wadadak.member.internal.social.SocialProvider;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.modulith.test.AssertablePublishedEvents;
import org.springframework.test.context.ActiveProfiles;

import java.sql.Timestamp;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RegionEventBackfillTest {

    @Autowired
    RegionEventBackfill backfill;

    @Autowired
    MemberRepository memberRepository;

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void republishesSignupRegionOnceWithSignupTime(AssertablePublishedEvents events) {
        Member member = memberRepository.save(Member.join(new SocialAccount(SocialProvider.KAKAO, "backfill-" + UUID.randomUUID()),
                "백필러너", null, "1129000000", null, RunningExperience.MONTHS_6, null, null));
        jdbc.update("INSERT INTO member.region_event_backfill (member_id) VALUES (?)", member.getId());
        Timestamp joinedAt = jdbc.queryForObject("SELECT created_at FROM member.members WHERE id = ?", Timestamp.class,
                member.getId());

        backfill.republish();
        backfill.republish();   // 대기열이 비어 다시 보내지 않는다

        // 가입 때 지역처럼 이전 지역 없이, 가입 시각으로 보낸다(ranking이 가입한 주부터 넣는다)
        assertThat(events.ofType(MemberRegionChangedEvent.class)
                .matching(e -> e.memberId().equals(member.getId())))
                .singleElement()
                .satisfies(e -> {
                    assertThat(e.regionCode()).isEqualTo("1129000000");
                    assertThat(e.previousRegionCode()).isNull();
                    assertThat(e.occurredAt()).isEqualTo(joinedAt.toInstant());
                    assertThat(e.version()).isZero();
                });
        assertThat(jdbc.queryForObject("SELECT count(*) FROM member.region_event_backfill", Long.class)).isZero();
    }
}
