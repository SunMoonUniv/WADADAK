package com.wadadak.course.internal.course;

import com.wadadak.event.course.CourseStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface CourseRepository extends JpaRepository<Course, UUID> {

    boolean existsByNameKeyAndStatus(String nameKey, CourseStatus status);

    /** 활성 코스 중 같은 이름이 있는지. 공백·대소문자는 무시한다({@link CourseName#key(String)}). */
    default boolean existsActiveByName(String name) {
        return existsByNameKeyAndStatus(CourseName.key(name), CourseStatus.ACTIVE);
    }

    /** 완주 연장과 만료 배치가 같은 코스를 함께 바꾸지 않게 행을 잠그고 읽는다. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT c FROM Course c WHERE c.id = :id")
    Optional<Course> findForUpdate(UUID id);

    /** 만료 시각이 {@code before} 이하인 공개 코스. 먼저 만료된 코스부터 */
    @Query("SELECT c.id FROM Course c WHERE c.status = com.wadadak.event.course.CourseStatus.ACTIVE "
            + "AND c.expiresAt <= :before ORDER BY c.expiresAt, c.id")
    List<UUID> findExpiredIds(Instant before, Limit limit);

    /** {@code before} 이전에 숨긴 코스. 먼저 숨긴 코스부터 */
    @Query("SELECT c.id FROM Course c WHERE c.status = com.wadadak.event.course.CourseStatus.HIDDEN "
            + "AND c.hiddenAt <= :before ORDER BY c.hiddenAt, c.id")
    List<UUID> findHiddenIds(Instant before, Limit limit);

    /** 만료 시각이 [{@code from}, {@code to})인 공개 코스(만료 임박 알림) */
    @Query("SELECT new com.wadadak.course.internal.course.ExpiringCourse(c.id, c.creatorId, c.name, c.expiresAt) "
            + "FROM Course c WHERE c.status = com.wadadak.event.course.CourseStatus.ACTIVE "
            + "AND c.expiresAt >= :from AND c.expiresAt < :to ORDER BY c.id")
    List<ExpiringCourse> findExpiring(Instant from, Instant to);
}
