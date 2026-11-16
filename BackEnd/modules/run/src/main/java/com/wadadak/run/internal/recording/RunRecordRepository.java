package com.wadadak.run.internal.recording;

import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

interface RunRecordRepository extends JpaRepository<RunRecord, UUID> {
    // Project summary_json alone: history must not load route/lap JSON.
    @Query(value = """
            SELECT r.summary_json FROM run.records r JOIN run.sessions s ON s.id = r.id
            WHERE s.member_id = :memberId
            ORDER BY r.registered_at DESC, r.id DESC LIMIT :limit
            """, nativeQuery = true)
    List<String> findSummaries(UUID memberId, int limit);

    @Query(value = """
            SELECT r.summary_json FROM run.records r JOIN run.sessions s ON s.id = r.id
            WHERE s.member_id = :memberId AND (r.registered_at, r.id) < (:before, :beforeId)
            ORDER BY r.registered_at DESC, r.id DESC LIMIT :limit
            """, nativeQuery = true)
    List<String> findSummariesBefore(UUID memberId, Instant before, UUID beforeId, int limit);

    // ponytail: 목록 JSON을 매번 훑는다. 기록이 많아지면 기준 버전 컬럼을 따로 둔다
    @Query(value = """
            SELECT r.id FROM run.records r
            WHERE coalesce(r.summary_json::jsonb #>> '{gpsGap,version}', '') <> :version
            ORDER BY r.registered_at, r.id LIMIT :limit
            """, nativeQuery = true)
    List<UUID> findGpsGapOutdated(String version, int limit);

    @Query("select r.id from RunRecord r where r.registrationPublished = false order by r.registeredAt, r.id")
    List<UUID> findUnpublishedIds(Pageable page);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from RunRecord r where r.id = :id and r.registrationPublished = false")
    Optional<RunRecord> findUnpublishedForUpdate(UUID id);
}
