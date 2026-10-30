package com.wadadak.course.internal.mine;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseName;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.Retention;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** {@link MyCourses} 실제 구현. {@code app.stub.course-mine: true}면 {@link MyCoursesStub}이 대신 뜬다(개발 정책 3.2). */
@Service
@ConditionalOnProperty(name = "app.stub.course-mine", havingValue = "false", matchIfMissing = true)
@RequiredArgsConstructor
class MyCourseService implements MyCourses {

    private final MyCourseRepository repository;
    private final CourseRepository courseRepository;
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
        // 만료 배치 · 완주 연장과 같은 코스를 함께 바꾸지 않게 잠근다
        Course course = courseRepository.findForUpdate(courseId)
                .orElseThrow(() -> new AppException(CourseErrorCode.COURSE_NOT_FOUND));
        if (!course.getCreatorId().equals(memberId)) {
            throw new AppException(CommonErrorCode.FORBIDDEN);
        }
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

    private Instant expiringSoonBefore() {
        return Retention.expiringSoonBefore(LocalDate.ofInstant(clock.instant(), TimeConfig.SEOUL));
    }
}
