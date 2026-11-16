package com.wadadak.course.internal.registration;

import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.Difficulty;
import jakarta.validation.constraints.NotNull;

import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * GPS 주행 등록 코스(D4). 서버는 {@code segments}로 경로를 다시 만들고 확인한다(미리보기 결과를 그대로 믿지 않는다).
 *
 * @param sourceRunRecordId 코스로 만들 러닝 기록 ID. 같은 기록은 한 번만 등록한다
 * @param segments          그 기록의 course-source {@code segments}(달린 순서의 경로 조각)
 * @param name              2~50자. 공백·대소문자만 다른 활성 코스 이름이 있으면 COURSE-006
 * @param tags              선택. 없으면 빈 목록
 */
record RegisterGpsCourseRequest(
        @NotNull UUID sourceRunRecordId,
        @NotNull List<@NotNull List<@NotNull GpsSourcePoint>> segments,
        @NotNull String name,
        @NotNull Difficulty difficulty,
        Set<@NotNull CourseTag> tags) {

    Set<CourseTag> tagsOrEmpty() {
        return tags == null ? Set.of() : tags;
    }
}
