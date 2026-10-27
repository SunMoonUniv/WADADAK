package com.wadadak.run.internal.recording;

import com.wadadak.run.internal.RunContracts.*;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.json.JsonMapper;

@Repository
class FreeGhostRepository {
    record Saved(UUID owner, String referenceHash, GhostStartApproval approval) {}
    private final JdbcTemplate db;
    private final JsonMapper json;
    FreeGhostRepository(JdbcTemplate db, JsonMapper json) { this.db=db; this.json=json; }
    Optional<Saved> find(UUID id) {
        return db.query("SELECT member_id,reference_hash,approval_json FROM run.free_ghost_starts WHERE session_id=?",
            (r,n)->new Saved(r.getObject(1,UUID.class),r.getString(2),json.readValue(r.getString(3),GhostStartApproval.class)),id)
            .stream().findFirst();
    }
    void save(UUID owner, String hash, GhostStartApproval approval) {
        db.update("INSERT INTO run.free_ghost_starts(session_id,member_id,reference_hash,approval_json) VALUES (?,?,?,?)",
            approval.sessionId(),owner,hash,json.writeValueAsString(approval));
    }
}
