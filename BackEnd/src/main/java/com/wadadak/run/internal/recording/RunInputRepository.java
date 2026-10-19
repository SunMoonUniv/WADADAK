package com.wadadak.run.internal.recording;

import com.wadadak.run.internal.RunContracts.Input;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.json.JsonMapper;

/** Raw GPS, sensor and lifecycle inputs share one ordered, immutable JDBC stream. */
@Repository
class RunInputRepository {
    private final JdbcTemplate db;
    private final NamedParameterJdbcTemplate named;
    private final JsonMapper json;

    RunInputRepository(JdbcTemplate db, JsonMapper json) {
        this.db = db;
        this.named = new NamedParameterJdbcTemplate(db);
        this.json = json;
    }

    Map<Long, Input> findExisting(UUID sessionId, List<Long> sequences) {
        if (sequences.isEmpty()) return Map.of();
        Map<Long, Input> existing = new HashMap<>();
        named.query("""
                SELECT stream_seq, payload FROM run.inputs
                WHERE session_id = :sessionId AND stream_seq IN (:sequences)
                """, Map.of("sessionId", sessionId, "sequences", sequences),
                rs -> { existing.put(rs.getLong(1), json.readValue(rs.getString(2), Input.class)); });
        return existing;
    }

    void insertBatch(UUID sessionId, Collection<Input> inputs) {
        if (inputs.isEmpty()) return;
        db.batchUpdate("INSERT INTO run.inputs(session_id,stream_seq,payload) VALUES (?,?,?)",
                inputs, 500, (statement, input) -> {
                    statement.setObject(1, sessionId);
                    statement.setLong(2, input.seq());
                    statement.setString(3, json.writeValueAsString(input));
                });
    }

    long count(UUID sessionId) {
        return db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?", Long.class, sessionId);
    }

    List<Long> sequences(UUID sessionId) {
        return db.query("SELECT stream_seq FROM run.inputs WHERE session_id=? ORDER BY stream_seq",
                (rs, n) -> rs.getLong(1), sessionId);
    }

    List<Input> findAll(UUID sessionId) {
        return db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",
                (rs, n) -> json.readValue(rs.getString(1), Input.class), sessionId);
    }

    void delete(UUID sessionId) {
        db.update("DELETE FROM run.inputs WHERE session_id=?", sessionId);
    }
}
