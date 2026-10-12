package com.wadadak.common.paging;

import java.util.List;

/**
 * 커서 페이징 응답(개발 정책 7장).
 *
 * @param nextCursor 다음 페이지를 요청할 때 {@code cursor}에 넣는 값. 마지막 페이지면 {@code null}
 */
public record CursorSlice<T>(List<T> content, String nextCursor) {
}
