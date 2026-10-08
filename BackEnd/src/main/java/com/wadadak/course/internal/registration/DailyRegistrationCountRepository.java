package com.wadadak.course.internal.registration;

import com.wadadak.course.internal.course.CourseType;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import java.time.LocalDate;
import java.util.Optional;
import java.util.UUID;

interface DailyRegistrationCountRepository extends JpaRepository<DailyRegistrationCount, UUID> {

    /** 그날 첫 등록이면 0건 행을 만든다. 동시에 두 요청이 와도 한 행만 생긴다. */
    @Modifying
    @Query(value = """
            INSERT INTO course.daily_registration_counts (id, member_id, registration_date, course_type, registered_count, created_at, updated_at)
            VALUES (:id, :memberId, :date, :courseType, 0, now(), now())
            ON CONFLICT (member_id, registration_date, course_type) DO NOTHING""", nativeQuery = true)
    void insertIfAbsent(UUID id, UUID memberId, LocalDate date, String courseType);

    /** 같은 회원의 동시 등록이 한도를 함께 넘지 않게 행을 잠그고 읽는다. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<DailyRegistrationCount> findByMemberIdAndRegistrationDateAndCourseType(UUID memberId, LocalDate registrationDate,
                                                                                     CourseType courseType);
}
