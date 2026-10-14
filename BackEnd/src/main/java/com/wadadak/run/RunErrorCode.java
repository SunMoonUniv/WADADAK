package com.wadadak.run;

import com.wadadak.common.exception.ErrorCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum RunErrorCode implements ErrorCode {
    INVALID(HttpStatus.BAD_REQUEST, "RUN-001", "러닝 입력을 확인해 주세요."),
    NOT_FOUND(HttpStatus.NOT_FOUND, "RUN-002", "러닝 기록을 찾을 수 없어요."),
    CONFLICT(HttpStatus.CONFLICT, "RUN-003", "이미 저장한 러닝 입력과 다른 내용이에요.");
    private final HttpStatus status;
    private final String code;
    private final String message;
}
