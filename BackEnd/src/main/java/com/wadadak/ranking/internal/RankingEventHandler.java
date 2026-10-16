package com.wadadak.ranking.internal;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.member.MemberRegionChangedEvent;
import com.wadadak.event.member.MemberVisibilityChangedEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.temporal.TemporalAdjusters;
import java.util.UUID;

/**
 * 다른 모듈 이벤트를 ranking 복사본에 반영한다. 중복·순서 역전에도 결과가 같다(개발 정책 5.4).
 * 메서드 이름은 이벤트 처리 기록의 키라서 바꾸지 않는다.
 */
@Component
@RequiredArgsConstructor
class RankingEventHandler {

    private final JdbcClient jdbc;

    /** 상태 복사형. 삭제면 그 코스의 랭킹 엔트리도 지운다. 복사본 행은 남겨 늦게 온 완주 기록을 받지 않는다. */
    @ApplicationModuleListener
    public void on(CourseStatusChangedEvent event) {
        jdbc.sql("""
                        INSERT INTO ranking.course_status_copies AS c (course_id, status, source_version, created_at, updated_at)
                        VALUES (:courseId, :status, :version, now(), now())
                        ON CONFLICT (course_id) DO UPDATE
                            SET status = EXCLUDED.status, source_version = EXCLUDED.source_version, updated_at = now()
                            WHERE c.source_version < EXCLUDED.source_version""")
                .param("courseId", event.courseId())
                .param("status", event.status().name())
                .param("version", event.version())
                .update();
        if (event.status() == CourseStatus.DELETED) {
            jdbc.sql("DELETE FROM ranking.course_ranking_entries WHERE course_id = :courseId")
                    .param("courseId", event.courseId())
                    .update();
        }
    }

    /** 상태 복사형. 비공개 회원은 순위 계산과 고스트 후보에서 빠진다. 기록은 남겨 다시 공개하면 그대로 보인다. */
    @ApplicationModuleListener
    public void on(MemberVisibilityChangedEvent event) {
        jdbc.sql("""
                        INSERT INTO ranking.member_visibility_copies AS v (member_id, visible, source_version, created_at, updated_at)
                        VALUES (:memberId, :visible, :version, now(), now())
                        ON CONFLICT (member_id) DO UPDATE
                            SET visible = EXCLUDED.visible, source_version = EXCLUDED.source_version, updated_at = now()
                            WHERE v.source_version < EXCLUDED.source_version""")
                .param("memberId", event.memberId())
                .param("visible", event.visible())
                .param("version", event.version())
                .update();
    }

    /**
     * 회원 지역 이력. 가입 때 지역은 가입한 주부터, 바꾼 지역은 바꾼 다음 주 월요일부터 지역 주간 랭킹에 들어간다(정책 공통 6).
     * 이벤트 하나가 한 행이라 순서가 바뀌어 와도 주마다 고르는 지역이 같다. 탈퇴 뒤에 온 이벤트는 받지 않는다.
     */
    @ApplicationModuleListener
    public void on(MemberRegionChangedEvent event) {
        lockMember(event.memberId());
        if (jdbc.sql("SELECT EXISTS (SELECT 1 FROM ranking.withdrawn_members WHERE member_id = :memberId)")
                .param("memberId", event.memberId()).query(Boolean.class).single()) {
            return;
        }
        LocalDate week = LocalDate.ofInstant(event.occurredAt(), TimeConfig.SEOUL)
                .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        LocalDate from = event.previousRegionCode() == null ? week : week.plusWeeks(1);
        jdbc.sql("""
                        INSERT INTO ranking.member_region_history (member_id, source_version, region_code, effective_from,
                            created_at, updated_at)
                        VALUES (:memberId, :version, :regionCode, :effectiveFrom, now(), now())
                        ON CONFLICT (member_id, source_version) DO NOTHING""")
                .param("memberId", event.memberId())
                .param("version", event.version())
                .param("regionCode", event.regionCode())
                .param("effectiveFrom", from.atStartOfDay(TimeConfig.SEOUL).toOffsetDateTime())
                .update();
    }

    /** 탈퇴 회원의 랭킹 기록·지역 이력을 바로 지운다. 탈퇴 표시를 남겨 늦게 온 기록·지역 이벤트를 받지 않는다. */
    @ApplicationModuleListener
    public void on(MemberWithdrawnEvent event) {
        lockMember(event.memberId());
        jdbc.sql("DELETE FROM ranking.distance_run_records WHERE member_id=:memberId")
                .param("memberId", event.memberId()).update();
        jdbc.sql("""
                        INSERT INTO ranking.withdrawn_members (member_id, withdrawn_at, created_at, updated_at)
                        VALUES (:memberId, :withdrawnAt, now(), now())
                        ON CONFLICT (member_id) DO NOTHING""")
                .param("memberId", event.memberId())
                .param("withdrawnAt", OffsetDateTime.ofInstant(event.withdrawnAt(), ZoneOffset.UTC))
                .update();
        jdbc.sql("DELETE FROM ranking.course_ranking_entries WHERE member_id = :memberId")
                .param("memberId", event.memberId())
                .update();
        jdbc.sql("DELETE FROM ranking.member_visibility_copies WHERE member_id = :memberId")
                .param("memberId", event.memberId())
                .update();
        jdbc.sql("DELETE FROM ranking.member_region_history WHERE member_id = :memberId")
                .param("memberId", event.memberId())
                .update();
    }

    /** 탈퇴와 그 회원의 다른 이벤트를 차례로 처리한다. {@link RunDistanceEventHandler}와 같은 키다. */
    private void lockMember(UUID memberId) {
        jdbc.sql("SELECT pg_advisory_xact_lock(hashtextextended(:key,0))")
                .param("key", "ranking-member:" + memberId).query((rs,n) -> true).list();
    }
}
