package com.wadadak.course.internal.registration;

import com.wadadak.common.entity.BaseEntity;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

/**
 * 회원·날짜(Asia/Seoul)·유형별 성공한 등록 수(정책 공통 3). 실패·멱등 중복 요청은 세지 않는다.
 */
@Getter
@Entity
@Table(schema = "course", name = "daily_registration_counts")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class DailyRegistrationCount extends BaseEntity<DailyRegistrationKey> {

    @EmbeddedId
    private DailyRegistrationKey id;

    private int registeredCount;

    DailyRegistrationCount(DailyRegistrationKey id) {
        this.id = id;
    }

    /** 한도 안이면 1 늘리고 {@code true}, 이미 한도면 그대로 두고 {@code false}. */
    boolean tryIncrement(int limit) {
        if (registeredCount >= limit) {
            return false;
        }
        registeredCount++;
        return true;
    }
}
