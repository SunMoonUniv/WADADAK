package com.wadadak.run.internal.recording;

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
    GhostComparisonStore(JdbcTemplate db, JsonMapper json, RunInputRepository inputs) {
        this.db = db;
        this.json = json;
        this.inputs = inputs;
    }

    void capture(UUID owner, GhostStartApproval approval) {
        boolean free = approval.course().courseId() == null;
        boolean publicSource = approval.publicPeriod() != null;
        UUID sourceOwner = db.query("SELECT member_id FROM run.sessions WHERE id=?",
                (rs, row) -> rs.getObject(1, UUID.class), approval.sourceRecordId())
                .stream().findFirst().orElse(null);
        var context = new ComparisonContext(approval.playback(),
                free ? "OWN_FREE" : publicSource ? "PUBLIC_COURSE" : "OWN_COURSE",
                publicSource ? approval.publicPeriod().name() : null, sourceOwner,
                sourceMetrics(owner, sourceOwner, approval), !free, previousBest(owner, approval));
        db.update("""
                INSERT INTO run.ghost_comparisons
                    (session_id, registered_session_id, free_session_id, member_id, context_json)
                VALUES (?,?,?,?,?)
                """, approval.sessionId(), free ? null : approval.sessionId(),
                free ? approval.sessionId() : null, owner, json.writeValueAsString(context));
    }

    private SourceComparisonMetrics sourceMetrics(UUID owner, UUID sourceOwner, GhostStartApproval approval) {
        if (approval.publicPeriod() != null || !owner.equals(sourceOwner)) return null;
        var raw = inputs.findAll(approval.sourceRecordId());
        long end = approval.playback().durationMs();
        return new SourceComparisonMetrics(GhostComparisonBuilder.activeMs(raw, end),
                GhostComparisonBuilder.cadence(raw, end));
    }

    private Long previousBest(UUID owner, GhostStartApproval approval) {
        if (approval.course().courseId() == null) return null;
        // Same route/order and integer distance, including linked GPS registration sources.
        var cutoff = approval.startedAt().isBefore(approval.approvedAt())
                ? approval.startedAt() : approval.approvedAt();
        String route = json.writeValueAsString(approval.course().route());
        Long baseline = db.queryForObject("""
                SELECT min((r.result_json::jsonb #>> '{course,courseElapsedSeconds}')::bigint)
                FROM run.records r JOIN run.sessions s ON s.id=r.id
                JOIN run.course_attempts a ON a.session_id=r.id
                WHERE s.member_id=? AND r.id<>? AND r.registered_at<? AND a.course_id=?
                  AND a.total_distance_meters=? AND a.route_json::jsonb=?::jsonb
                  AND r.result_json::jsonb #>> '{course,completed}'='true'
                """, Long.class, owner, approval.sessionId(), Timestamp.from(cutoff),
                approval.course().courseId(), approval.course().totalDistanceMeters(), route);
        Long linkedBest = db.queryForObject("""
                SELECT min(l.course_elapsed_seconds) FROM run.gps_source_links l
                WHERE l.member_id=? AND l.status='LINKED' AND l.source_record_id<>? AND l.registered_at<?
                  AND l.linked_at<? AND l.course_id=?
                  AND (l.snapshot_json::jsonb ->> 'distanceMeters')::integer=?
                  AND l.snapshot_json::jsonb -> 'route'=?::jsonb
                """, Long.class, owner, approval.sessionId(), Timestamp.from(cutoff), Timestamp.from(cutoff),
                approval.course().courseId(), approval.course().totalDistanceMeters(), route);
        if (linkedBest == null) return baseline;
        if (baseline == null) return linkedBest;
        return Math.min(baseline, linkedBest);
    }

    private Optional<ComparisonContext> context(UUID id) {
        return db.query("SELECT context_json FROM run.ghost_comparisons WHERE session_id=?",
                (rs, row) -> json.readValue(rs.getString(1), ComparisonContext.class), id).stream().findFirst();
    }

    void finish(GhostOutcome outcome, List<Input> raw) {
        var context = context(outcome.sessionId());
        // Old approvals retain their existing verdict, without invented metadata.
        if (context.isEmpty()) return;
        var detail = GhostComparisonBuilder.build(context.get(), outcome, raw);
        db.update("UPDATE run.ghost_comparisons SET result_json=?,updated_at=now() WHERE session_id=? AND result_json IS NULL",
                json.writeValueAsString(detail), outcome.sessionId());
    }

    GhostComparison get(UUID owner, GhostOutcome result) {
        // Parse the frozen context once inside PostgreSQL; transfer only the result and live state.
        // The replay remains available to finish(), but is never deserialized for a result read.
        return db.query("""
                WITH snapshot AS MATERIALIZED (
                    SELECT result_json, context_json::jsonb AS context
                    FROM run.ghost_comparisons WHERE session_id=? AND member_id=?
                )
                SELECT result_json,
                    CASE
                        WHEN EXISTS(SELECT 1 FROM run.withdrawn_members
                            WHERE member_id=(context ->> 'sourceOwner')::uuid) THEN 'WITHDRAWN'
                        WHEN EXISTS(SELECT 1 FROM run.deleted_records WHERE id=?) THEN 'DELETED'
                        WHEN context ->> 'kind'='PUBLIC_COURSE' AND EXISTS(
                            SELECT 1 FROM run.member_visibility_copies
                            WHERE member_id=(context ->> 'sourceOwner')::uuid AND NOT visible) THEN 'PRIVATE'
                        ELSE 'AVAILABLE'
                    END AS source_state
                FROM snapshot
                """, (rs, row) -> {
                    String saved = rs.getString("result_json");
                    GhostComparison detail = saved == null
                            ? GhostComparisonBuilder.unavailable(result, "LEGACY_NO_DETAIL")
                            : json.readValue(saved, GhostComparison.class);
                    return detail.withSourceState(rs.getString("source_state"));
                }, result.sessionId(), owner, result.sourceRecordId()).stream().findFirst()
                .orElseGet(() -> GhostComparisonBuilder.unavailable(result, "LEGACY_NO_DETAIL"));
    }
}
