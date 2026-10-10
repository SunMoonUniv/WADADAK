package com.wadadak.course;

import com.wadadak.common.exception.ErrorCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum CourseErrorCode implements ErrorCode {
    COURSE_NOT_FOUND(HttpStatus.NOT_FOUND, "COURSE-001", "코스를 찾을 수 없습니다."),
    COURSE_NOT_AVAILABLE(HttpStatus.CONFLICT, "COURSE-002", "비공개되었거나 삭제된 코스입니다."),
    ROUTE_TOO_FEW_POINTS(HttpStatus.BAD_REQUEST, "COURSE-003", "경로 지점은 2개 이상이어야 합니다."),
    ROUTE_TOO_SHORT(HttpStatus.BAD_REQUEST, "COURSE-004", "코스 거리는 1km 이상이어야 합니다."),
    ROUTE_TOO_LONG(HttpStatus.BAD_REQUEST, "COURSE-005", "직접 만든 코스는 100km를 넘을 수 없습니다."),
    NAME_TAKEN(HttpStatus.CONFLICT, "COURSE-006", "이미 사용 중인 코스 이름입니다."),
    SIMILAR_COURSE_EXISTS(HttpStatus.CONFLICT, "COURSE-007", "기존 코스와 85% 이상 겹쳐 등록할 수 없습니다."),
    // 요청 내용이 아니라 횟수 제한이라 429. 다음 날 00:00(Asia/Seoul)에 풀린다
    DAILY_LIMIT_EXCEEDED(HttpStatus.TOO_MANY_REQUESTS, "COURSE-008", "오늘 등록할 수 있는 코스 수를 넘었습니다."),
    // 출발점이 육지 경계에서 약 100m 넘게 떨어진 경우(바다·경계 데이터에 없는 섬). 지역 없는 코스는 지역 집계·검색에서 빠지므로 받지 않는다
    START_REGION_NOT_FOUND(HttpStatus.BAD_REQUEST, "COURSE-009", "코스 출발점의 지역을 확인할 수 없습니다.");

    private final HttpStatus status;
    private final String code;
    private final String message;
}
