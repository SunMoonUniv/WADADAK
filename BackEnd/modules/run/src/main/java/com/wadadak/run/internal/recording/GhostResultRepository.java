package com.wadadak.run.internal.recording;

import com.wadadak.run.internal.RunContracts.GhostOutcome;
import java.sql.Timestamp;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.json.JsonMapper;

/** Caller holds the same member/session locks as record processing and deletion. */
@Repository
class GhostResultRepository {
    record Opponent(UUID sourceRecordId, long elapsedSeconds, long durationMs) {}
    private final JdbcTemplate db;
    private final JsonMapper json;
    private final FreeGhostRepository freeGhosts;

    @org.springframework.beans.factory.annotation.Autowired
    GhostResultRepository(JdbcTemplate db, JsonMapper json, FreeGhostRepository freeGhosts) { this.db = db; this.json = json; this.freeGhosts=freeGhosts; }
    GhostResultRepository(JdbcTemplate db, JsonMapper json) { this(db,json,new FreeGhostRepository(db,json)); }

    Optional<Opponent> opponent(UUID id) {
        // Judging survives source deletion and does not depend on retained playback detail.
        var registered = db.query("SELECT source_record_id, source_elapsed_seconds, source_duration_ms FROM run.ghost_starts WHERE session_id=?",
                (rs, n) -> new Opponent(rs.getObject(1, UUID.class), rs.getLong(2), rs.getLong(3)), id).stream().findFirst();
        return registered.or(()->freeGhosts.find(id).map(saved->{var a=saved.approval();
            return new Opponent(a.sourceRecordId(),a.playback().courseElapsedSeconds(),a.playback().durationMs());}));
    }

    Optional<GhostOutcome> find(UUID id) {
        return db.query("SELECT result_json FROM run.ghost_results WHERE session_id=? UNION ALL SELECT result_json FROM run.free_ghost_results WHERE session_id=?",
                (rs, n) -> json.readValue(rs.getString(1), GhostOutcome.class), id,id).stream().findFirst();
    }

    void save(UUID id, GhostOutcome result) {
        String table="GHOST_RESULT_FREE_V1".equals(result.version())?"free_ghost_results":"ghost_results";
        db.update("INSERT INTO run."+table+"(session_id, finalized_at, result_json) VALUES (?, ?, ?)",
                id, Timestamp.from(result.finalizedAt()), json.writeValueAsString(result));
    }
}
