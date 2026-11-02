package com.wadadak.course.internal.bookmark;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.event.course.CourseStatus;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 저장한 코스 카드(G5 · C8). 카드의 `8.1km · 난이도 상 · ★ 4.4`, `만든 사람 러너_하늘`, `만료 D-18`과 썸네일이다.
 *
 * @param averageRating   전체 기간 평점(소수 첫째 자리 반올림, 목록 카드와 같다). 리뷰가 없으면 {@code null}
 * @param creatorNickname 등록자 닉네임. 탈퇴했으면 `탈퇴한 사용자`, 회원 정보를 받지 못하면 {@code null}
 * @param route           카드 썸네일. 첫 점이 출발점
 * @param status          ACTIVE 공개 중, HIDDEN 삭제 예정(만료됐거나 등록자가 삭제해 비공개). 삭제가 끝난 코스는 목록에 없다
 * @param expiresAt       공개 만료 시각(만료일 23:59:59 Asia/Seoul). 카드의 `만료 D-n`
 * @param deleteAt        삭제 예정 시각(비공개 시각 + 24시간). ACTIVE면 {@code null}
 */
record BookmarkItem(
        UUID courseId,
        String name,
        int distanceMeters,
        Difficulty difficulty,
        Double averageRating,
        UUID creatorId,
        String creatorNickname,
        List<GeoPoint> route,
        CourseStatus status,
        Instant expiresAt,
        Instant deleteAt) {

    BookmarkItem withCreatorNickname(String nickname) {
        return new BookmarkItem(courseId, name, distanceMeters, difficulty, averageRating, creatorId, nickname, route, status,
                expiresAt, deleteAt);
    }
}
