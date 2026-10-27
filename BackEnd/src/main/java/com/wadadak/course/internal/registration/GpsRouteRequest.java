package com.wadadak.course.internal.registration;

import jakarta.validation.constraints.NotNull;

import java.util.List;
import java.util.UUID;

/**
 * D4 코스 경로 미리보기.
 *
 * @param sourceRunRecordId 코스로 만들 러닝 기록 ID
 * @param segments          그 기록의 course-source {@code segments}(달린 순서의 경로 조각)
 */
record GpsRouteRequest(@NotNull UUID sourceRunRecordId,
                       @NotNull List<@NotNull List<@NotNull GpsSourcePoint>> segments) {
}
