package com.wadadak.course.internal.mine;

import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.Difficulty;
import jakarta.validation.constraints.NotNull;

import java.util.Set;

/**
 * 코스 수정(B7). 이름 · 난이도 · 특징을 모두 보낸다(전체 교체). 경로 · 유형은 바꿀 수 없다(정책 공통 3).
 *
 * @param name 2~50자. 다른 공개 코스와 같은 이름(공백 · 대소문자 무시)이면 COURSE-006. 지금 이 코스 이름은 그대로 둬도 된다
 * @param tags 선택. 없으면 특징을 모두 뺀다
 */
record EditCourseRequest(@NotNull String name, @NotNull Difficulty difficulty, Set<@NotNull CourseTag> tags) {

    Set<CourseTag> tagsOrEmpty() {
        return tags == null ? Set.of() : tags;
    }
}
