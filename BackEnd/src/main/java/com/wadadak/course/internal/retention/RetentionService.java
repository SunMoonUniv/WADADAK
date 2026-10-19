package com.wadadak.course.internal.retention;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.entity.UuidV7;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.ExpiringCourse;
import com.wadadak.course.internal.stats.CourseStatsService;
import com.wadadak.event.course.CourseExpiringSoonEvent;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.course.CourseStatusReason;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * 유지 기간 · 만료(정책 공통 4, 개발 정책 6.2). 코스마다 트랜잭션을 나눠, 한 코스가 실패해도 다른 코스는 바뀐다.
 * 상태를 바꾸면 같은 트랜잭션에서 {@link CourseStatusChangedEvent}를 발행한다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
class RetentionService {

    /** 비공개에서 삭제까지 */
    static final Duration DELETE_AFTER = Duration.ofHours(24);

    private final CourseRepository courseRepository;
    private final CourseStatsService courseStats;
    private final ApplicationEventPublisher events;
    private final Clock clock;

    /** 서버가 확정한 완주로 연장한다. 비공개 · 삭제 · 없는 코스와 만료 뒤에 받은 완주는 그대로 둔다(정책 공통 4 · D-10) */
    @Transactional
    boolean extend(UUID courseId, Instant registeredAt) {
        Course course = courseRepository.findForUpdate(courseId).orElse(null);
        if (course == null || !course.extendByCompletion(registeredAt, clock.instant())) {
            return false;
        }
        log.info("코스 유지 기간 연장 courseId={} expiresAt={}", courseId, course.getExpiresAt());
        return true;
    }

    /** 만료된 코스를 비공개로 바꾼다. 그 사이 완주로 연장됐으면 그대로 둔다 */
    @Transactional
    boolean hideIfExpired(UUID courseId) {
        Instant now = clock.instant();
        Course course = courseRepository.findForUpdate(courseId).orElse(null);
        if (course == null || !course.isExpiredAt(now)) {
            return false;
        }
        course.hide(CourseStatusReason.EXPIRED, now);
        publishStatus(course, now);
        return true;
    }

    /** 숨긴 지 24시간 지난 코스를 삭제로 바꾸고 그 코스의 통계를 지운다(개발 정책 6.2). 만료 · 등록자 삭제 모두 같다 */
    @Transactional
    boolean deleteIfDue(UUID courseId) {
        Instant now = clock.instant();
        Course course = courseRepository.findForUpdate(courseId).orElse(null);
        if (course == null || course.getStatus() != CourseStatus.HIDDEN
                || now.isBefore(course.getHiddenAt().plus(DELETE_AFTER))) {
            return false;
        }
        course.delete();
        courseStats.deleteFor(courseId);
        publishStatus(course, now);
        return true;
    }

    /**
     * 만료일이 {@code today}부터 {@code daysLeft}일 뒤인 공개 코스마다 만료 임박 이벤트를 발행한다.
     * 아웃박스에 기록을 쓰므로 읽기 전용 트랜잭션이 아니다.
     */
    @Transactional
    int publishExpiringSoon(LocalDate today, int daysLeft) {
        LocalDate expiryDate = today.plusDays(daysLeft);
        List<ExpiringCourse> courses = courseRepository.findExpiring(
                expiryDate.atStartOfDay(TimeConfig.SEOUL).toInstant(),
                expiryDate.plusDays(1).atStartOfDay(TimeConfig.SEOUL).toInstant());
        Instant now = clock.instant();
        for (ExpiringCourse course : courses) {
            events.publishEvent(new CourseExpiringSoonEvent(UuidV7.create(), now, course.id(), course.creatorId(),
                    course.name(), course.expiresAt(), daysLeft));
        }
        return courses.size();
    }

    private void publishStatus(Course course, Instant now) {
        // @Version은 flush할 때 오른다. 바뀐 값을 실어야 상태가 바뀔 때마다 수신 측이 더 큰 버전을 받는다
        courseRepository.flush();
        events.publishEvent(new CourseStatusChangedEvent(UuidV7.create(), now, course.getId(), course.getStatus(),
                course.getStatusReason(), course.getVersion()));
        log.info("코스 상태 변경 courseId={} status={} reason={} version={}", course.getId(), course.getStatus(),
                course.getStatusReason(), course.getVersion());
    }
}
