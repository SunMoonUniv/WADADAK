package com.wadadak.course.internal.explore;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * 현재 러너 수를 물을 코스들. 같은 ID를 여러 번 보내도 한 번으로 본다.
 *
 * @param courseIds 1 ~ {@link CourseMapRepository#MAX_RUNNER_COURSES}개
 */
record CourseActiveRunnersRequest(@NotEmpty @Size(max = CourseMapRepository.MAX_RUNNER_COURSES) List<UUID> courseIds) {

    Set<UUID> ids() {
        return new LinkedHashSet<>(courseIds);
    }
}
