package com.wadadak.course.internal.registration;

import com.wadadak.course.internal.course.CourseType;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import java.time.LocalDate;
import java.util.Optional;
import java.util.UUID;

interface DailyRegistrationCountRepository extends JpaRepository<DailyRegistrationCount, UUID> {

    /** 같은 회원의 동시 등록이 한도를 함께 넘지 않게 행을 잠그고 읽는다. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<DailyRegistrationCount> findByMemberIdAndRegistrationDateAndCourseType(UUID memberId, LocalDate registrationDate,
                                                                                     CourseType courseType);
}
