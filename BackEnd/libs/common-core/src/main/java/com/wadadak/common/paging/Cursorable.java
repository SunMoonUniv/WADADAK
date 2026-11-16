package com.wadadak.common.paging;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
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

    /**
     * 오프셋 커서(0부터 시작하는 위치)로 읽는다. 커서가 비어 있으면 0이다.
     *
     * @throws AppException {@link CommonErrorCode#INVALID_REQUEST} — 0 이상의 정수가 아닌 커서
     */
    public int offset() {
        if (cursor == null || cursor.isBlank()) {
            return 0;
        }
        try {
            int offset = Integer.parseInt(cursor);
            if (offset >= 0) {
                return offset;
            }
        } catch (NumberFormatException ignored) {
            // 아래에서 잘못된 커서로 거절한다
        }
        throw new AppException(CommonErrorCode.INVALID_REQUEST, "cursor: 잘못된 값입니다.");
    }
}
