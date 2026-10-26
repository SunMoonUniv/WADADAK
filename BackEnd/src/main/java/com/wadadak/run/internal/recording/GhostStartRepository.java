package com.wadadak.run.internal.recording;

import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.common.geo.GeoPoint;
import java.sql.Timestamp;
import java.util.Optional;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.json.JsonMapper;

/** Run-owned durable receipt and separate derived replay. Caller holds member/session locks. */
@Repository
class GhostStartRepository {
    private final JdbcTemplate db;
    private final JsonMapper json;

    GhostStartRepository(JdbcTemplate db, JsonMapper json) {
        this.db = db;
        this.json = json;
    }

    Optional<GhostStartApproval> find(UUID id) {
        return db.query("""
                SELECT s.*, p.playback_json, c.course_id, c.course_name, c.course_version,
                    c.route_json, c.total_distance_meters FROM run.ghost_starts s
                JOIN run.ghost_start_playbacks p USING (session_id)
                JOIN run.course_attempts c USING (session_id) WHERE s.session_id=?
                """, (rs, n) -> new GhostStartApproval(rs.getString("approval_version"), id,
                rs.getObject("source_record_id", UUID.class), rs.getTimestamp("started_at").toInstant(),
                rs.getTimestamp("approved_at").toInstant(), rs.getTimestamp("course_validated_at").toInstant(),
                new CourseSnapshot(id, rs.getObject("course_id", UUID.class), rs.getString("course_name"),
                    List.of(json.readValue(rs.getString("route_json"), GeoPoint[].class)),
                    rs.getInt("total_distance_meters"), rs.getLong("course_version")),
                json.readValue(rs.getString("playback_json"), GhostPlayback.class)), id).stream().findFirst();
    }

    void save(GhostStartApproval approval) {
        db.update("""
                INSERT INTO run.ghost_starts(session_id, source_record_id, started_at, approved_at,
                    course_validated_at, approval_version, playback_version, source_policy_version,
                    source_calculation_version, source_elapsed_seconds, source_duration_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, approval.sessionId(), approval.sourceRecordId(), Timestamp.from(approval.startedAt()),
                Timestamp.from(approval.approvedAt()), Timestamp.from(approval.courseValidatedAt()), approval.version(),
                approval.playback().version(), approval.playback().sourcePolicyVersion(),
                approval.playback().sourceCalculationVersion(), approval.playback().courseElapsedSeconds(),
                approval.playback().durationMs());
        db.update("INSERT INTO run.ghost_start_playbacks(session_id, playback_json) VALUES (?, ?)",
                approval.sessionId(), json.writeValueAsString(approval.playback()));
    }
}
