package com.wadadak.common.exception;

import com.wadadak.common.response.ApiResult;
import lombok.extern.slf4j.Slf4j;
import org.jspecify.annotations.Nullable;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.BindException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/**
 * package-private: Modulith 관측 프록시 대상에서 빠진다. 프록시되면 부모의 final 메서드가 프록시 위에서 실행된다.
 */
@Slf4j
@RestControllerAdvice
class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    @ExceptionHandler(AppException.class)
    public ResponseEntity<ApiResult<Void>> handleApp(AppException e) {
        ErrorCode errorCode = e.getErrorCode();
        return ResponseEntity.status(errorCode.getStatus()).body(ApiResult.error(errorCode, e.getMessage()));
    }

    /** 사전 확인을 통과한 동시 요청(버튼 연타 등)이 유니크 제약에 걸린 경우. */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ApiResult<Void>> handleConflict(DataIntegrityViolationException e) {
        log.warn("제약 조건 위반: {}", e.getMostSpecificCause().getMessage());
        return ResponseEntity.status(CommonErrorCode.CONFLICT.getStatus()).body(ApiResult.error(CommonErrorCode.CONFLICT));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResult<Void>> handleUnexpected(Exception e) {
        log.error("처리되지 않은 예외", e);
        return ResponseEntity.internalServerError().body(ApiResult.error(CommonErrorCode.INTERNAL_ERROR));
    }

    /** Spring MVC 표준 예외(검증 실패·잘못된 본문·404·405 등)도 ApiResult로 감싼다. */
    @Override
    protected ResponseEntity<Object> handleExceptionInternal(Exception ex, @Nullable Object body, HttpHeaders headers,
                                                             HttpStatusCode statusCode, WebRequest request) {
        CommonErrorCode errorCode = switch (statusCode.value()) {
            case 404 -> CommonErrorCode.NOT_FOUND;
            case 405 -> CommonErrorCode.METHOD_NOT_ALLOWED;
            default -> statusCode.is5xxServerError() ? CommonErrorCode.INTERNAL_ERROR : CommonErrorCode.INVALID_REQUEST;
        };
        String message = errorCode.getMessage();
        if (ex instanceof BindException bind && bind.getFieldError() != null) {
            FieldError fieldError = bind.getFieldError();
            message = fieldError.getField() + ": " + fieldError.getDefaultMessage();
        }
        return ResponseEntity.status(statusCode).headers(headers).body(ApiResult.error(errorCode, message));
    }
}
