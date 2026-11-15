package com.wadadak.ranking.internal;

import com.wadadak.event.run.RunRecordDeletedEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;

/**
 * run 기록 이벤트를 누적 거리 복사본(F12)과 코스 랭킹 엔트리(F8)에 반영한다.
 * 둘을 한 트랜잭션에서 써서, 코스 랭킹도 기록마다 {@code distance_run_records}에 남는 삭제 표시를 그대로 쓴다.
 * 그래서 삭제가 완주보다 먼저 와도 되살아나지 않는다. 메서드 이름은 이벤트 처리 기록의 키라서 바꾸지 않는다.
 */
@Component
class RunDistanceEventHandler {
    private final JdbcTemplate db;
    RunDistanceEventHandler(JdbcTemplate db) { this.db = db; }
    private boolean withdrawn(UUID member) {
        db.query("SELECT pg_advisory_xact_lock(hashtextextended(?::text,0))",
                (rs,n) -> true, "ranking-member:" + member);
        return db.queryForObject("SELECT count(*) FROM ranking.withdrawn_members WHERE member_id=?", Long.class, member) > 0;
    }
    @ApplicationModuleListener
    public void on(RunSessionEndedEvent event) {
        if (withdrawn(event.memberId())) return;
        copy(event.runRecordId(), event.memberId(), event.distanceMeters(), event.registeredAt(), false);
        if (event.courseId() != null && event.completed()) enterCourseRanking(event);
    }
    @ApplicationModuleListener
    public void on(RunRecordDeletedEvent event) {
        if (withdrawn(event.memberId())) return;
        copy(event.runRecordId(), event.memberId(), event.distanceMeters(), event.registeredAt(), true);
        db.update("UPDATE ranking.course_ranking_entries SET deleted=true, updated_at=now() WHERE run_record_id=?",
                event.runRecordId());
    }
    private void copy(UUID record, UUID member, double distance, Instant registered, boolean deleted) {
        db.update("""
                INSERT INTO ranking.distance_run_records(run_record_id,member_id,distance_meters,registered_at,deleted)
                VALUES (?,?,?,?,?) ON CONFLICT (run_record_id) DO UPDATE
                SET deleted = ranking.distance_run_records.deleted OR EXCLUDED.deleted, updated_at=now()
                """, record, member, distance, Timestamp.from(registered), deleted);
    }
    /**
     * 완주 기록 1건을 코스 랭킹에 넣는다(삽입형). 숨김·삭제된 코스에는 새로 넣지 않는다(정책 공통 4).
     * 삭제 여부는 방금 쓴 누적 거리 복사본에서 가져온다.
     */
    private void enterCourseRanking(RunSessionEndedEvent e) {
        // ponytail: 코스 상태 이벤트와 잠금 없이 동시에 처리되면 숨김·삭제된 코스에 행이 남을 수 있다. 조회가 그런 코스를 통째로 거르므로 보이지 않는다
        db.update("""
                INSERT INTO ranking.course_ranking_entries(run_record_id,course_id,member_id,course_elapsed_seconds,
                    course_distance_meters,completed_at,registered_at,deleted,created_at,updated_at)
                SELECT ?,?,?,?,?,?,?,d.deleted,now(),now() FROM ranking.distance_run_records d
                WHERE d.run_record_id=? AND NOT EXISTS (SELECT 1 FROM ranking.course_status_copies WHERE course_id=?)
                ON CONFLICT (run_record_id) DO NOTHING
                """, e.runRecordId(), e.courseId(), e.memberId(), e.courseElapsedSeconds(), e.courseDistanceMeters(),
                Timestamp.from(e.completedAt()), Timestamp.from(e.registeredAt()), e.runRecordId(), e.courseId());
    }
}
