package com.wadadak.course.internal.registration;

import com.wadadak.course.internal.course.CourseType;
import jakarta.persistence.Embeddable;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.time.LocalDate;
import java.util.UUID;

@Getter
@Embeddable
@EqualsAndHashCode
@AllArgsConstructor
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class DailyRegistrationKey implements Serializable {

    private UUID memberId;

    /** Asia/Seoul 날짜 */
    private LocalDate registrationDate;

    @Enumerated(EnumType.STRING)
    private CourseType courseType;
}
