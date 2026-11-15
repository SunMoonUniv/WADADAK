package com.wadadak.common.exception;

import org.springframework.http.HttpStatus;

/**
 * 에러 코드 공통 인터페이스. 모듈마다 자기 루트 패키지에 구현 enum을 둔다({@code CourseErrorCode} 등).
 * 코드 문자열은 모듈 접두사를 붙인다({@code COURSE-001}).
 */
public interface ErrorCode {

    HttpStatus getStatus();

    String getCode();

    String getMessage();
}
