package com.wadadak.common.exception;

import lombok.Getter;

/**
 * 비즈니스 예외. 응답 상태·코드는 {@link ErrorCode}가 정한다.
 */
@Getter
public class AppException extends RuntimeException {

    private final ErrorCode errorCode;

    public AppException(ErrorCode errorCode) {
        super(errorCode.getMessage());
        this.errorCode = errorCode;
    }

    public AppException(ErrorCode errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }
}
