package com.wadadak.course.internal.mine;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseName;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.Retention;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.course.CourseStatusReason;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** {@link MyCourses} 실제 구현. {@code app.stub.course-mine: true}면 {@link MyCoursesStub}이 대신 뜬다(개발 정책 3.2). */
@Slf4j
@Service
@ConditionalOnProperty(name = "app.stub.course-mine", havingValue = "false", matchIfMissing = true)
@RequiredArgsConstructor
class MyCourseService implements MyCourses {

    private final MyCourseRepository repository;
    private final CourseRepository courseRepository;
    private final ApplicationEventPublisher events;
    private final Clock clock;

    @Override
    @Transactional(readOnly = true)
    public CursorSlice<MyCourseItem> list(UUID memberId, Cursorable page) {
        return repository.list(memberId, expiringSoonBefore(), page);
    }

    @Override
    @Transactional(readOnly = true)
    public MyCourseSummary summary(UUID memberId) {
        return repository.summary(memberId, expiringSoonBefore());
    }

    /** 이름 길이(001) → 없음(COURSE-001) → 남의 코스(003) → 공개 중 아님 · 만료(COURSE-002) → 이름 중복(006) */
    @Override
    @Transactional
    public MyCourseItem edit(UUID memberId, UUID courseId, EditCourseRequest request) {
        String name = CourseName.requireValid(request.name());
        Course course = lockMine(memberId, courseId);
        // 만료 시각이 지나 배치가 곧 비공개로 바꿀 코스도 막는다
        if (!course.isActive() || course.isExpiredAt(clock.instant())) {
            throw new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE);
        }
        if (courseRepository.existsActiveByNameExcept(name, courseId)) {
            throw new AppException(CourseErrorCode.NAME_TAKEN);
        }
        course.edit(name, request.difficulty(), request.tagsOrEmpty());
        // 카드는 JDBC로 다시 읽으므로 먼저 반영한다. 같은 이름으로 동시에 바꾸면 여기서 유니크 제약에 걸린다(COMMON-007)
        courseRepository.flush();
        return repository.find(courseId);
    }

    /**
     * 없음(COURSE-001) → 남의 코스(003) → 삭제가 끝남(COURSE-002). 이미 삭제 예정(만료 · 등록자 삭제)이면 바꾸지 않는다.
     * 만료 시각이 지나 배치를 기다리는 코스는 아직 공개 중이라 등록자 삭제로 숨긴다.
     */
    @Override
    @Transactional
    public MyCourseItem delete(UUID memberId, UUID courseId) {
        Course course = lockMine(memberId, courseId);
        if (course.getStatus() == CourseStatus.DELETED) {
            throw new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE);
        }
        if (course.isActive()) {
            Instant now = clock.instant();
            course.hide(CourseStatusReason.USER_DELETED, now);
            // @Version은 flush할 때 오른다. 만료 배치처럼 바뀐 버전을 싣고, 카드도 JDBC로 다시 읽으므로 먼저 반영한다
            courseRepository.flush();
            events.publishEvent(new CourseStatusChangedEvent(UuidV7.create(), now, course.getId(), course.getStatus(),
                    course.getStatusReason(), course.getVersion()));
            log.info("코스 상태 변경 courseId={} status={} reason={} version={}", course.getId(), course.getStatus(),
                    course.getStatusReason(), course.getVersion());
        }
        return repository.find(courseId);
    }

    /** 만료 배치 · 완주 연장과 같은 코스를 함께 바꾸지 않게 잠근다. 없으면 COURSE-001, 남의 코스면 COMMON-003 */
    private Course lockMine(UUID memberId, UUID courseId) {
        Course course = courseRepository.findForUpdate(courseId)
                .orElseThrow(() -> new AppException(CourseErrorCode.COURSE_NOT_FOUND));
        if (!course.getCreatorId().equals(memberId)) {
            throw new AppException(CommonErrorCode.FORBIDDEN);
        }
        return course;
    }

    private Instant expiringSoonBefore() {
        return Retention.expiringSoonBefore(LocalDate.ofInstant(clock.instant(), TimeConfig.SEOUL));
    }
}
