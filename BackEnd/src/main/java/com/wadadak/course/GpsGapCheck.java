package com.wadadak.course;

/**
 * GPS 코스 등록의 끊긴 구간 기준으로 본 기록 경로 판단({@link CourseApi#checkGpsGaps}).
 *
 * @param passed  빈칸을 모두 이을 수 있으면 true. false면 B6 · 결과 화면 사유 {@code GPS 정확도 부족}
 * @param version 판단한 기준 버전(지금 {@code GPS_GAP_V1}). 기준이 바뀌면 올라가므로, 저장한 판단의 버전이 다르면 다시 판단한다.
 */
public record GpsGapCheck(boolean passed, String version) {
}
