package com.wadadak.run.internal.recording;

import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** Transaction-scoped locks also protect IDs whose session row does not exist yet. */
@Repository
class RunLocks {
    private final JdbcTemplate db;

    RunLocks(JdbcTemplate db) {
        this.db = db;
    }

    void member(UUID memberId) {
        acquire("run-member:" + memberId);
    }

    void session(UUID sessionId) {
        acquire(sessionId.toString());
    }

    private void acquire(String key) {
        db.query("SELECT pg_advisory_xact_lock(hashtextextended(?::text,0))", (rs, n) -> true, key);
    }
}
