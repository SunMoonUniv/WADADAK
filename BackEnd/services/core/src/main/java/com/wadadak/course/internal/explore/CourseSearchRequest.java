package com.wadadak.course.internal.explore;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.course.internal.course.CourseName;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 코스 검색어(SEA-01 · SEA-03). 정렬 · 현재 위치는 {@link CourseListRequest}로 따로 받는다.
 *
 * @param query 검색어. 공백을 빼고 2글자 이상
 */
record CourseSearchRequest(@NotNull @Size(max = MAX_LENGTH) String query) {

    /** 검색어 길이 상한 */
    static final int MAX_LENGTH = 100;

    /**
     * 이름 중복 검사와 같은 키({@link CourseName#key})로 바꾼 검색어. 공백과 대소문자를 보지 않는다.
     *
     * @throws AppException COMMON-001 — 공백을 빼고 2글자 미만
     */
    String key() {
        return keyOf(query);
    }

    /**
     * [query]를 이름 키로 바꾼다. 검색(G1 · G6)과 G6에서 고른 검색어 조건(홈 지도 · 목록, {@link CourseMapRequest#query})이 함께 쓴다.
     *
     * @throws AppException COMMON-001 — 공백을 빼고 2글자 미만
     */
    static String keyOf(String query) {
        String key = CourseName.key(query);
        if (key.codePointCount(0, key.length()) < CourseName.MIN_LENGTH) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST,
                    "검색어는 공백을 빼고 " + CourseName.MIN_LENGTH + "글자 이상이어야 합니다.");
        }
        return key;
    }
}
