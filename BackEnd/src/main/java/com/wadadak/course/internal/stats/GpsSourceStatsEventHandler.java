package com.wadadak.course.internal.stats;

import com.wadadak.event.run.GpsSourceLinkedEvent;
import com.wadadak.event.run.GpsSourceUnlinkedEvent;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

/** A source contributes only one completion. A per-source tombstone handles duplicates and removal-first delivery. */
@Component
class GpsSourceStatsEventHandler {
    private final JdbcTemplate db;
    private final CourseStatsRepository stats;
    GpsSourceStatsEventHandler(JdbcTemplate db,CourseStatsRepository stats) {this.db=db;this.stats=stats;}

    @ApplicationModuleListener
    public void on(GpsSourceLinkedEvent e) {
        if(!stats.markProcessed(e.eventId(),"course.gps-source-linked")) return;
        String status=lockCourse(e.courseId());
        receipt(e,false);
        var state=lockReceipt(e.runRecordId());
        if(!"ACTIVE".equals(status) || state.removed() || state.applied()) return;
        stats.addCompletions(e.courseId(),1,e.courseElapsedSeconds());
        stats.addCompletion(e.runRecordId(),e.courseId(),e.completedAt());
        db.update("UPDATE course.gps_source_completion_receipts SET applied=true,updated_at=now() WHERE run_record_id=?",e.runRecordId());
    }

    @ApplicationModuleListener
    public void on(GpsSourceUnlinkedEvent event) {
        if(!stats.markProcessed(event.eventId(),"course.gps-source-unlinked")) return;
        var e=event.source();
        String status=lockCourse(e.courseId());
        receipt(e,true);
        var state=lockReceipt(e.runRecordId());
        if(state.applied() && status!=null && !"DELETED".equals(status)) {
            stats.addCompletions(e.courseId(),-1,-e.courseElapsedSeconds());
            stats.removeCompletion(e.runRecordId(),e.courseId());
        }
        db.update("UPDATE course.gps_source_completion_receipts SET removed=true,applied=false,updated_at=now() WHERE run_record_id=?",e.runRecordId());
    }
    private String lockCourse(UUID id) {
        return db.query("SELECT status FROM course.courses WHERE id=? FOR SHARE",(r,n)->r.getString(1),id)
                .stream().findFirst().orElse(null);
    }
    private void receipt(GpsSourceLinkedEvent e,boolean removed) {
        db.update("""
            INSERT INTO course.gps_source_completion_receipts(run_record_id,course_id,member_id,course_elapsed_seconds,removed)
            VALUES (?,?,?,?,?) ON CONFLICT(run_record_id) DO NOTHING
            """,e.runRecordId(),e.courseId(),e.memberId(),e.courseElapsedSeconds(),removed);
    }
    private record State(boolean applied,boolean removed) {}
    private State lockReceipt(UUID id) {
        return db.queryForObject("SELECT applied,removed FROM course.gps_source_completion_receipts WHERE run_record_id=? FOR UPDATE",
                (r,n)->new State(r.getBoolean(1),r.getBoolean(2)),id);
    }
}
