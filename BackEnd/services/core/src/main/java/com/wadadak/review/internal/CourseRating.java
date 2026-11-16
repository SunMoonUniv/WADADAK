package com.wadadak.review.internal;

import java.util.UUID;

/**
 * 코스 하나의 평점. 지도 핀(A5-01)처럼 여러 코스를 한 번에 보여줄 때 쓴다.
 * 리뷰 수는 주지 않는다. 핀에는 평점만 나오고, 코스 카드의 평점·리뷰 수는 코스 목록 API(course 코스 통계)가 준다.
 *
 * @param averageRating 전체 별점 평균(소수 첫째 자리 반올림). 리뷰가 없거나 숨김·삭제된 코스면 {@code null}
 */
record CourseRating(UUID courseId, Double averageRating) {

    static CourseRating none(UUID courseId) {
        return new CourseRating(courseId, null);
    }
}
