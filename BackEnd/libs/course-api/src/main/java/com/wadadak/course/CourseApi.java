package com.wadadak.course;

import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * 러닝 준비·시작용 코스 경로 조회(호출 허용: run), 운영자 화면의 코스 이름 표시(호출 허용: review). 개발 정책 4.3.
 * 시작 시 받은 스냅샷으로 러닝을 끝까지 진행한다. 이후 코스가 비공개·삭제돼도 다시 조회하지 않는다(6.2).
 * <p>
 * 스텁({@code app.stub.course: true})은 어떤 ID든 약 1km 직선 코스를 돌려준다. 에러 확인용 ID:
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
     * 코스 이름 일괄 조회(운영자 리뷰 관리 ADM-2의 코스 칸). 비공개 · 삭제된 코스도 이름을 돌려주고, 없는 ID는 결과에서 빠진다.
     * 한 번에 100개까지 부른다(다른 일괄 조회와 같다, 개발 정책 4.2).
     */
    Map<UUID, String> getNames(Set<UUID> courseIds);
}
