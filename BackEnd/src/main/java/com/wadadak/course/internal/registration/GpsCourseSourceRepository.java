package com.wadadak.course.internal.registration;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.UUID;

interface GpsCourseSourceRepository extends JpaRepository<GpsCourseSource, UUID> {

    boolean existsByRunRecordId(UUID runRecordId);

    /** 회원이 GPS 코스 등록에 쓴 러닝 기록. 등록한 순서 */
    @Query("SELECT s.runRecordId FROM GpsCourseSource s WHERE s.memberId = :memberId ORDER BY s.createdAt, s.courseId")
    List<UUID> findRunRecordIdsByMemberId(UUID memberId);
}
