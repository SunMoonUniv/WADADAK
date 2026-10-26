package com.wadadak.course;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;
import java.util.UUID;

/**
 * 러닝 준비·시작용 코스 경로 조회와 GPS 코스 등록 기준 판단. 호출 허용: run (개발 정책 4.3).
 * 시작 시 받은 스냅샷으로 러닝을 끝까지 진행한다. 이후 코스가 비공개·삭제돼도 다시 조회하지 않는다(6.2).
 * <p>
 * 스텁({@code app.stub.course: true})은 어떤 ID든 약 1km 직선 코스를 돌려주고, GPS 기준 판단은 실제와 같다. 에러 확인용 ID:
 * <ul>
 *     <li>{@code 00000000-0000-0000-0000-000000000001} → {@link CourseErrorCode#COURSE_NOT_FOUND}</li>
 *     <li>{@code 00000000-0000-0000-0000-000000000002} → {@link CourseErrorCode#COURSE_NOT_AVAILABLE}</li>
 * </ul>
 */
public interface CourseApi {

    /**
     * @throws com.wadadak.common.exception.AppException {@link CourseErrorCode#COURSE_NOT_FOUND} — 없는 코스,
     *         {@link CourseErrorCode#COURSE_NOT_AVAILABLE} — {@code ACTIVE}가 아닌 코스(비공개·삭제)
     */
    CourseRouteSnapshot getRouteForRun(UUID courseId);

    /**
     * 기록 경로를 GPS 코스 등록의 끊긴 구간 기준(정책 문서 4.1 `공통 3 GPS 등록 끊긴 구간 · B6-04`)으로 판단한다.
     * run이 기록 결과를 계산할 때 한 번 불러 저장하고, 기록 목록 · 결과 조회에 실어 B6 · 결과 화면의
     * {@code GPS 정확도 부족}을 보인다. 코스 등록(D4)도 같은 기준으로 다시 확인한다.
     * <p>
     * 계산만 하고 DB를 읽지 않는다. 그래도 분리 후에는 네트워크 호출이므로 쓰기 트랜잭션 밖에서 부른다(개발 정책 4.4).
     *
     * @param segments course-source {@code segments}와 같은 경로 조각(달린 순서)
     */
    GpsGapCheck checkGpsGaps(List<List<GeoPoint>> segments);
}
