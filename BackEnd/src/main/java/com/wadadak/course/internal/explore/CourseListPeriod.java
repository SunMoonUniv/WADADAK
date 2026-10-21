package com.wadadak.course.internal.explore;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import org.springframework.format.annotation.DateTimeFormat;

import java.time.LocalDate;

/**
 * 인기순 기간(FIL-09, A3 기간 슬라이더). Asia/Seoul 날짜이고 두 날짜를 모두 포함한다. 코스 일별 통계의 날짜와 같은 기준이다.
 * 정렬 순서만 바꾸고 코스를 빼지 않아, 지도 · 지역별 코스 수 · 예상 코스 수와는 상관없다.
 *
 * @param startDate 시작일. 보내지 않으면 처음부터
 * @param endDate   종료일. 보내지 않으면 끝없이
 */
record CourseListPeriod(
        @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate startDate,
        @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate endDate) {

    /**
     * [sort]에 쓸 기간. 두 날짜를 모두 보내지 않았으면 null(전체 기간)이다.
     *
     * @throws AppException COMMON-001 — 인기순이 아닌데 기간을 보냈거나, 시작일이 종료일보다 늦을 때
     */
    CourseListPeriod requireFor(CourseListSort sort) {
        if (startDate == null && endDate == null) {
            return null;
        }
        if (sort != CourseListSort.POPULAR) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "기간(startDate · endDate)은 인기순(POPULAR)에만 보냅니다.");
        }
        if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "기간 시작일(startDate)이 종료일(endDate)보다 늦습니다.");
        }
        return this;
    }
}
