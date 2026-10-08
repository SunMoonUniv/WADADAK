package com.wadadak.course.internal.registration;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

import java.util.Optional;

interface DailyRegistrationCountRepository extends JpaRepository<DailyRegistrationCount, DailyRegistrationKey> {

    /** 같은 회원의 동시 등록이 한도를 함께 넘지 않게 행을 잠그고 읽는다. */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT d FROM DailyRegistrationCount d WHERE d.id = :id")
    Optional<DailyRegistrationCount> findForUpdate(DailyRegistrationKey id);
}
