package com.wadadak.course.internal.course;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusReason;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** 유지 기간 고정 구간 · 연장 · 만료 경계(정책 공통 4 · D-10). 시각은 Asia/Seoul = UTC+9로 적는다. */
class CourseRetentionTest {

    @Test
    void initialExpiryIsThirtiethDayIncludingRegistrationDay() {
        assertThat(Retention.initialExpiresAt(LocalDate.of(2026, 10, 1))).isEqualTo(seoul("2026-10-30T23:59:59"));
    }

    /** 정책 공통 4의 예: 10/1 등록, 10/5 완주 → 11/29, 10/10 완주 → 그대로, 10/31~11/29 완주 → 12/29 */
    @Test
    void extendsOncePerFixedPeriodWhoeverFinishes() {
        Course course = course(LocalDate.of(2026, 10, 1));

        assertThat(finish(course, seoul("2026-10-05T08:00:00"))).isTrue();
        assertThat(course.getExpiresAt()).isEqualTo(seoul("2026-11-29T23:59:59"));

        assertThat(finish(course, seoul("2026-10-10T08:00:00"))).isFalse();
        assertThat(finish(course, seoul("2026-10-05T08:00:00"))).as("같은 완주가 다시 와도").isFalse();
        assertThat(course.getExpiresAt()).isEqualTo(seoul("2026-11-29T23:59:59"));

        assertThat(finish(course, seoul("2026-10-31T00:00:00"))).isTrue();
        assertThat(course.getExpiresAt()).isEqualTo(seoul("2026-12-29T23:59:59"));
        assertThat(finish(course, seoul("2026-11-29T23:59:59"))).isFalse();
    }

    @Test
    void lateArrivalOfEarlierPeriodDoesNotExtendAgain() {
        Course course = course(LocalDate.of(2026, 10, 1));
        finish(course, seoul("2026-10-05T08:00:00"));
        finish(course, seoul("2026-11-03T08:00:00"));

        // 앞 구간(10/1~10/30)의 다른 완주가 늦게 와도 그 구간은 이미 연장했다
        assertThat(finish(course, seoul("2026-10-20T08:00:00"))).isFalse();
        assertThat(course.getExpiresAt()).isEqualTo(seoul("2026-12-29T23:59:59"));
    }

    @Test
    void registeredUntilLastSecondOfExpiryDayExtends() {
        Course lastMoment = course(LocalDate.of(2026, 10, 1));
        assertThat(finish(lastMoment, seoul("2026-10-30T23:59:59.999"))).isTrue();

        Course nextDay = course(LocalDate.of(2026, 10, 1));
        assertThat(finish(nextDay, seoul("2026-10-31T00:00:00"))).as("만료일 다음 날 00:00부터는 만료").isFalse();
        assertThat(nextDay.getExpiresAt()).isEqualTo(seoul("2026-10-30T23:59:59"));
    }

    @Test
    void expiresFromNextDayMidnight() {
        Course course = course(LocalDate.of(2026, 10, 1));

        assertThat(course.isExpiredAt(seoul("2026-10-30T23:59:59.999"))).isFalse();
        assertThat(course.isExpiredAt(seoul("2026-10-31T00:00:00"))).isTrue();
    }

    @Test
    void hiddenCourseIsNeitherExtendedNorExpiredAgain() {
        Course course = course(LocalDate.of(2026, 10, 1));
        course.hide(CourseStatusReason.EXPIRED, seoul("2026-10-31T00:00:30"));

        assertThat(finish(course, seoul("2026-10-20T08:00:00"))).isFalse();
        assertThat(course.isExpiredAt(seoul("2026-11-30T00:00:00"))).isFalse();
        assertThat(course.getStatusReason()).isEqualTo(CourseStatusReason.EXPIRED);
        assertThat(course.getHiddenAt()).isEqualTo(seoul("2026-10-31T00:00:30"));
    }

    @Test
    void statusMovesOnlyForward() {
        Course course = course(LocalDate.of(2026, 10, 1));
        assertThatThrownBy(course::delete).isInstanceOf(IllegalStateException.class);

        course.hide(CourseStatusReason.USER_DELETED, seoul("2026-10-10T12:00:00"));
        assertThatThrownBy(() -> course.hide(CourseStatusReason.EXPIRED, seoul("2026-10-10T12:00:01")))
                .isInstanceOf(IllegalStateException.class);

        course.delete();
        assertThat(course.getStatus()).isEqualTo(CourseStatus.DELETED);
        assertThat(course.getStatusReason()).as("숨긴 사유를 그대로 둔다").isEqualTo(CourseStatusReason.USER_DELETED);
        assertThatThrownBy(course::delete).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void completionReceivedAfterExpiryDoesNotExtend() {
        Course course = course(LocalDate.of(2026, 10, 1));

        // 만료 10초 전에 등록된 완주를 만료 10초 뒤에 받았다. 배치가 아직 숨기지 않아 공개 중이어도 연장하지 않는다(정책 공통 4)
        assertThat(course.extendByCompletion(seoul("2026-10-30T23:59:50"), seoul("2026-10-31T00:00:10"))).isFalse();
        assertThat(course.isActive()).isTrue();
        assertThat(course.getExpiresAt()).isEqualTo(seoul("2026-10-30T23:59:59"));
    }

    /** 등록되자마자 받은 완주 */
    private static boolean finish(Course course, Instant registeredAt) {
        return course.extendByCompletion(registeredAt, registeredAt);
    }

    private static Course course(LocalDate registeredOn) {
        return Course.registerCustom(UUID.randomUUID(), "유지 기간 코스", Difficulty.MEDIUM, Set.of(),
                CourseGeometry.lineString(List.of(new GeoPoint(37.5000, 127.1000), new GeoPoint(37.5090, 127.1000))),
                1000, "1171010100", Retention.initialExpiresAt(registeredOn));
    }

    /** Asia/Seoul 시각 */
    private static Instant seoul(String localDateTime) {
        return Instant.parse(localDateTime + "+09:00");
    }
}
