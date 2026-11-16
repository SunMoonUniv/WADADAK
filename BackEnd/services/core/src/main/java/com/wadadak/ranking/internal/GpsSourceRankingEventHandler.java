package com.wadadak.ranking.internal;

import com.wadadak.event.run.GpsSourceLinkedEvent;
import com.wadadak.event.run.GpsSourceUnlinkedEvent;
import java.sql.Timestamp;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

/** Course entries only. Never inserts/updates distance_run_records, so source distance/count stay unchanged. */
@Component
class GpsSourceRankingEventHandler {
    private final JdbcTemplate db;
    GpsSourceRankingEventHandler(JdbcTemplate db) {this.db=db;}
    private boolean withdrawn(UUID id) {
        db.query("SELECT pg_advisory_xact_lock(hashtextextended(?::text,0))",(r,n)->true,"ranking-member:"+id);
        return Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM ranking.withdrawn_members WHERE member_id=?)",Boolean.class,id));
    }
    @ApplicationModuleListener
    public void on(GpsSourceLinkedEvent e) {
        if(withdrawn(e.memberId()))return;
        db.update("""
            INSERT INTO ranking.course_ranking_entries(run_record_id,course_id,member_id,course_elapsed_seconds,
                course_distance_meters,completed_at,registered_at,deleted,created_at,updated_at)
            SELECT ?,?,?,?,?,?,?,COALESCE((SELECT deleted FROM ranking.distance_run_records WHERE run_record_id=?),false),now(),now()
            WHERE NOT EXISTS(SELECT 1 FROM ranking.course_status_copies WHERE course_id=?)
            ON CONFLICT(run_record_id) DO NOTHING
            """,e.runRecordId(),e.courseId(),e.memberId(),e.courseElapsedSeconds(),e.courseDistanceMeters(),
                Timestamp.from(e.completedAt()),Timestamp.from(e.registeredAt()),e.runRecordId(),e.courseId());
    }
    @ApplicationModuleListener
    public void on(GpsSourceUnlinkedEvent event) {
        var e=event.source();
        if(withdrawn(e.memberId()))return;
        // A deleted entry is also the removal-first tombstone. No distance record is manufactured.
        db.update("""
            INSERT INTO ranking.course_ranking_entries(run_record_id,course_id,member_id,course_elapsed_seconds,
                course_distance_meters,completed_at,registered_at,deleted,created_at,updated_at)
            VALUES (?,?,?,?,?,?,?,true,now(),now())
            ON CONFLICT(run_record_id) DO UPDATE SET deleted=true,updated_at=now()
            """,e.runRecordId(),e.courseId(),e.memberId(),e.courseElapsedSeconds(),e.courseDistanceMeters(),
                Timestamp.from(e.completedAt()),Timestamp.from(e.registeredAt()));
    }
}
