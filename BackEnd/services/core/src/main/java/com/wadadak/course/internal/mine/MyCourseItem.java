package com.wadadak.course.internal.mine;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusReason;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * 내가 등록한 코스 카드(G4). B7 코스 수정 화면도 이 값으로 채운다. 평점 · 리뷰 수는 리뷰 API(/api/v1/reviews/summary)가 준다.
 *
 * @param courseType      카드의 `그려서 만든 코스`(CUSTOM) · `달려서 만든 코스`(GPS)
 * @param tags            FIL-04 순서
 * @param route           카드 · B7 지도 그림. 첫 점이 출발점
 * @param status          ACTIVE 공개 중, HIDDEN 삭제 예정(만료됐거나 내가 삭제해 비공개). 삭제가 끝난 코스는 목록에 없다
 * @param statusReason    HIDDEN이 된 사유(EXPIRED · USER_DELETED). ACTIVE면 {@code null}
 * @param expiresAt       공개 만료 시각(만료일 23:59:59 Asia/Seoul). 카드의 `만료 D-1`, B7의 `만료까지`
 * @param deleteAt        삭제 예정 시각(비공개 시각 + 24시간). ACTIVE면 {@code null}
 * @param completionCount `누적 주행 N회`. 서버가 확정한 완주 수이고, 개인 기록을 지우면 그 완주는 빠진다
 * @param lastCompletedOn `최근 주행`. 마지막으로 완주한 날(Asia/Seoul). 완주가 없으면 {@code null}
 */
record MyCourseItem(
        UUID courseId,
        String name,
        CourseType courseType,
        Difficulty difficulty,
        List<CourseTag> tags,
        List<GeoPoint> route,
        CourseStatus status,
        CourseStatusReason statusReason,
        Instant expiresAt,
        Instant deleteAt,
        int completionCount,
        LocalDate lastCompletedOn) {
}
