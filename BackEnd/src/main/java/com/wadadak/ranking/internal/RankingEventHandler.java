package com.wadadak.ranking.internal;

import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.member.MemberVisibilityChangedEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;

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

    /** 탈퇴 회원의 랭킹 기록을 바로 지운다. 탈퇴 표시를 남겨 늦게 온 완주 기록을 받지 않는다. */
    @ApplicationModuleListener
    public void on(MemberWithdrawnEvent event) {
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
    }
}
