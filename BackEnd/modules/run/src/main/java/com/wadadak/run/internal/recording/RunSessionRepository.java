package com.wadadak.run.internal.recording;

import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

interface RunSessionRepository extends JpaRepository<RunSession, UUID> {
    Optional<RunSession> findByIdAndMemberId(UUID id, UUID memberId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from RunSession s where s.id = :id and s.memberId = :memberId")
    Optional<RunSession> findOwnedForUpdate(UUID id, UUID memberId);

    // Read only the owner before acquiring advisory locks; do not cache a stale session entity.
    @Query("select s.memberId from RunSession s where s.id = :id")
    Optional<UUID> findMemberId(UUID id);

    @Query("select s.id from RunSession s where s.memberId = :memberId order by s.id")
    List<UUID> findIdsByMemberId(UUID memberId);

    @Query("select s.id from RunSession s where s.processing = 'PROCESSING' order by s.startedAt, s.id")
    List<UUID> findWaitingIds(Pageable page);

    @Query(value = "SELECT * FROM run.sessions WHERE id = :id AND processing = 'PROCESSING' FOR UPDATE SKIP LOCKED",
            nativeQuery = true)
    Optional<RunSession> findProcessingForUpdate(UUID id);
}
