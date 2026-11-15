package com.wadadak.common.response;

import com.wadadak.common.exception.ErrorCode;

/**
 * 모든 API 응답 래퍼. 성공이면 {@code data}, 실패면 {@code code}·{@code message}를 채운다.
 */
public record ApiResult<T>(ResultType result, T data, String code, String message) {

    public static <T> ApiResult<T> success(T data) {
        return new ApiResult<>(ResultType.SUCCESS, data, null, null);
    }

    public static ApiResult<Void> success() {
        return success(null);
    }

    public static ApiResult<Void> error(ErrorCode errorCode) {
        return error(errorCode, errorCode.getMessage());
    }

    public static ApiResult<Void> error(ErrorCode errorCode, String message) {
        return new ApiResult<>(ResultType.ERROR, null, errorCode.getCode(), message);
    }
}
