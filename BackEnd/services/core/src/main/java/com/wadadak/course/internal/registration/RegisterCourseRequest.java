package com.wadadak.course.internal.registration;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.course.internal.route.RouteService;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.Set;

/**
 * 사용자 지정 코스 등록(B4-07).
 *
 * @param anchorPoints B3 입력점. 최종 경로는 서버가 이것으로 다시 만든다(앱이 받은 경로를 그대로 믿지 않는다)
 * @param name         2~50자. 공백·대소문자만 다른 활성 코스 이름이 있으면 COURSE-006
 * @param tags         선택. 없으면 빈 목록
 */
record RegisterCourseRequest(
        @NotNull @Size(max = RouteService.MAX_ANCHOR_POINTS) List<@NotNull GeoPoint> anchorPoints,
        @NotNull String name,
        @NotNull Difficulty difficulty,
        Set<@NotNull CourseTag> tags) {

    Set<CourseTag> tagsOrEmpty() {
        return tags == null ? Set.of() : tags;
    }
}
