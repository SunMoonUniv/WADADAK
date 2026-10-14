package com.wadadak.ranking.internal;

import com.wadadak.event.run.RunRecordDeletedEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;

/** Own-schema copies for F12. Ranking UI/snapshot rules are not changed here. */
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
    }
    @ApplicationModuleListener
    public void on(RunRecordDeletedEvent event) {
        if (withdrawn(event.memberId())) return;
        copy(event.runRecordId(), event.memberId(), event.distanceMeters(), event.registeredAt(), true);
    }
    private void copy(UUID record, UUID member, double distance, Instant registered, boolean deleted) {
        db.update("""
                INSERT INTO ranking.distance_run_records(run_record_id,member_id,distance_meters,registered_at,deleted)
                VALUES (?,?,?,?,?) ON CONFLICT (run_record_id) DO UPDATE
                SET deleted = ranking.distance_run_records.deleted OR EXCLUDED.deleted, updated_at=now()
                """, record, member, distance, Timestamp.from(registered), deleted);
    }
}
