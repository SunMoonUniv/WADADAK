package com.wadadak.course.internal.explore;

import java.time.LocalDate;

/**
 * 인기순 기간(FIL-09, A3 기간 슬라이더). Asia/Seoul 날짜이고 두 날짜를 모두 포함한다. 코스 일별 통계의 날짜와 같은 기준이다.
 * 목록은 그 기간의 수로 정렬하고, 그 기간에 도전 · 조회 · 리뷰가 없는 코스는 지도 · 지역별 코스 수 · 목록에서 모두 빠진다.
 * 그 기간에 등록한 코스(등록일, Asia/Seoul)는 값이 없어도 남고 값이 0이라 뒤에 온다.
 * 요청의 {@link CourseMapRequest#period()}로 만든다.
 *
 * @param startDate 시작일. null이면 처음부터
 * @param endDate   종료일. null이면 끝없이
 */
record CourseListPeriod(LocalDate startDate, LocalDate endDate) {
}
