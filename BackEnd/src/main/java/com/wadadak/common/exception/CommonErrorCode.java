package com.wadadak.common.exception;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum CommonErrorCode implements ErrorCode {
    INVALID_REQUEST(HttpStatus.BAD_REQUEST, "COMMON-001", "잘못된 요청입니다."),
    UNAUTHORIZED(HttpStatus.UNAUTHORIZED, "COMMON-002", "인증이 필요합니다."),
    FORBIDDEN(HttpStatus.FORBIDDEN, "COMMON-003", "권한이 없습니다."),
    NOT_FOUND(HttpStatus.NOT_FOUND, "COMMON-004", "요청한 자원을 찾을 수 없습니다."),
    METHOD_NOT_ALLOWED(HttpStatus.METHOD_NOT_ALLOWED, "COMMON-005", "지원하지 않는 요청 방식입니다."),
    INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "COMMON-006", "서버 오류가 발생했습니다."),
    CONFLICT(HttpStatus.CONFLICT, "COMMON-007", "이미 처리되었거나 중복된 요청입니다.");

    private final HttpStatus status;
    private final String code;
    private final String message;
}
