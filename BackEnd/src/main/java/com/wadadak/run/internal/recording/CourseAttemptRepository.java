package com.wadadak.run.internal.recording;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

interface CourseAttemptRepository extends JpaRepository<CourseAttempt, UUID> {

    Optional<CourseAttempt> findByIdAndMemberId(UUID id, UUID memberId);

    // 잠금 전에 소유자만 읽는다. 엔티티를 미리 올려 두면 잠금 뒤 다시 읽을 때 낡은 값을 쓴다
    @Query("select a.memberId from CourseAttempt a where a.id = :id")
    Optional<UUID> findMemberId(UUID id);

    @Query("select a.id from CourseAttempt a where a.memberId = :memberId order by a.id")
    List<UUID> findIdsByMemberId(UUID memberId);

    @Query("select count(a) from CourseAttempt a where a.courseId = :courseId and a.startedAt is not null and a.releasedAt is null")
    long countActive(UUID courseId);

    @Query("select a.id from CourseAttempt a where a.startedAt < :startedBefore and a.releasedAt is null order by a.startedAt")
    List<UUID> findExpiredIds(Instant startedBefore, Pageable page);
}
