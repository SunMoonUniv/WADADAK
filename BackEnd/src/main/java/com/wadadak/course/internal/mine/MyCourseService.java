package com.wadadak.course.internal.mine;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
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

    private Instant expiringSoonBefore() {
        return Retention.expiringSoonBefore(LocalDate.ofInstant(clock.instant(), TimeConfig.SEOUL));
    }
}
