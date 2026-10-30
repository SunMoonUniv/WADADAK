package com.wadadak.run.internal.recording;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.RunContracts.*;
import java.sql.Timestamp;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.json.JsonMapper;

/** Snapshot and final detail share approval/process transactions and their existing locks. */
@Repository
class GhostComparisonStore {
    private final JdbcTemplate db;
    private final JsonMapper json;
    private final RunInputRepository inputs;
    GhostComparisonStore(JdbcTemplate db,JsonMapper json,RunInputRepository inputs) {
        this.db=db;this.json=json;this.inputs=inputs;
    }
    void capture(UUID owner,GhostStartApproval approval) {
        boolean free=approval.course().courseId()==null, publicSource=approval.publicPeriod()!=null;
        UUID sourceOwner=db.query("SELECT member_id FROM run.sessions WHERE id=?",(r,n)->r.getObject(1,UUID.class),
                approval.sourceRecordId()).stream().findFirst().orElse(null);
        SourceComparisonMetrics metrics=null;
        if(!publicSource && owner.equals(sourceOwner)) {
            var raw=inputs.findAll(approval.sourceRecordId());
            metrics=new SourceComparisonMetrics(GhostComparisonBuilder.activeMs(raw,approval.playback().durationMs()),
                    GhostComparisonBuilder.cadence(raw,approval.playback().durationMs()));
        }
        Long baseline=null;
        if(!free) {
            // Run-owned data only. Same route/order and integer distance, independent of profile visibility.
            var cutoff=approval.startedAt().isBefore(approval.approvedAt())?approval.startedAt():approval.approvedAt();
            baseline=db.queryForObject("""
                SELECT min((r.result_json::jsonb #>> '{course,courseElapsedSeconds}')::bigint)
                FROM run.records r JOIN run.sessions s ON s.id=r.id
                JOIN run.course_attempts a ON a.session_id=r.id
                WHERE s.member_id=? AND r.id<>? AND r.registered_at<? AND a.course_id=?
                  AND a.total_distance_meters=? AND a.route_json::jsonb=?::jsonb
                  AND r.result_json::jsonb #>> '{course,completed}'='true'
                """,Long.class,owner,approval.sessionId(),Timestamp.from(cutoff),approval.course().courseId(),
                    approval.course().totalDistanceMeters(),json.writeValueAsString(approval.course().route()));
        }
        var context=new ComparisonContext(approval.playback(),free?"OWN_FREE":publicSource?"PUBLIC_COURSE":"OWN_COURSE",
                approval.publicPeriod()==null?null:approval.publicPeriod().name(),sourceOwner,metrics,!free,baseline);
        db.update("INSERT INTO run.ghost_comparisons(session_id,registered_session_id,free_session_id,member_id,context_json) VALUES (?,?,?,?,?)",
                approval.sessionId(),free?null:approval.sessionId(),free?approval.sessionId():null,owner,json.writeValueAsString(context));
    }
    private Optional<ComparisonContext> context(UUID id) {
        return db.query("SELECT context_json FROM run.ghost_comparisons WHERE session_id=?",
                (r,n)->json.readValue(r.getString(1),ComparisonContext.class),id).stream().findFirst();
    }
    void finish(GhostOutcome outcome,List<Input> raw) {
        var context=context(outcome.sessionId());
        if(context.isEmpty())return; // Old approvals retain their existing verdict, without invented metadata.
        var detail=GhostComparisonBuilder.build(context.get(),outcome,raw);
        db.update("UPDATE run.ghost_comparisons SET result_json=?,updated_at=now() WHERE session_id=? AND result_json IS NULL",
                json.writeValueAsString(detail),outcome.sessionId());
    }
    GhostComparison get(UUID owner,GhostOutcome result) {
        var saved=db.query("SELECT result_json FROM run.ghost_comparisons WHERE session_id=? AND member_id=? AND result_json IS NOT NULL",
                (r,n)->json.readValue(r.getString(1),GhostComparison.class),result.sessionId(),owner).stream().findFirst();
        GhostComparison detail=saved.orElseGet(()->GhostComparisonBuilder.unavailable(result,"LEGACY_NO_DETAIL"));
        var context=context(result.sessionId());
        if(context.isEmpty())return detail;
        var c=context.get();
        String state="AVAILABLE";
        if(c.sourceOwner()!=null && exists("SELECT EXISTS(SELECT 1 FROM run.withdrawn_members WHERE member_id=?)",c.sourceOwner()))state="WITHDRAWN";
        else if(exists("SELECT EXISTS(SELECT 1 FROM run.deleted_records WHERE id=?)",result.sourceRecordId()))state="DELETED";
        else if(c.kind().equals("PUBLIC_COURSE") && c.sourceOwner()!=null &&
                exists("SELECT EXISTS(SELECT 1 FROM run.member_visibility_copies WHERE member_id=? AND NOT visible)",c.sourceOwner()))state="PRIVATE";
        return detail.withSourceState(state);
    }
    private boolean exists(String query,UUID id){return Boolean.TRUE.equals(db.queryForObject(query,Boolean.class,id));}
}
