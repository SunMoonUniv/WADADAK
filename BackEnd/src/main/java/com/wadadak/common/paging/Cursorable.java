package com.wadadak.common.paging;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

/**
 * 커서 페이징 요청(개발 정책 7장). 컨트롤러에서 {@code @ParameterObject @Valid Cursorable page}로 쿼리 파라미터를 받는다.
 *
 * @param cursor 이전 응답의 {@link CursorSlice#nextCursor()}. 첫 페이지면 비운다
 * @param size   한 페이지 개수. 비우면 {@value #DEFAULT_SIZE}, 최대 {@value #MAX_SIZE}
 */
public record Cursorable(String cursor, @Min(1) @Max(MAX_SIZE) Integer size) {

    public static final int DEFAULT_SIZE = 20;
    public static final int MAX_SIZE = 50;

    public Cursorable {
        if (size == null) {
            size = DEFAULT_SIZE;
        }
    }
}
