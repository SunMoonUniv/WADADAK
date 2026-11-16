package com.wadadak.common.paging;

import java.util.List;
import java.util.function.Function;

/**
 * 커서 페이징 응답(개발 정책 7장).
 *
 * @param nextCursor 다음 페이지를 요청할 때 {@code cursor}에 넣는 값. 마지막 페이지면 {@code null}
 */
public record CursorSlice<T>(List<T> content, String nextCursor) {

    /** 전체 목록에서 오프셋 커서({@link Cursorable#offset()})로 한 페이지를 자른다. */
    public static <T> CursorSlice<T> ofOffset(List<T> all, Cursorable page) {
        int from = Math.min(page.offset(), all.size());
        int to = Math.min(from + page.size(), all.size());
        return new CursorSlice<>(all.subList(from, to), to < all.size() ? String.valueOf(to) : null);
    }

    public <R> CursorSlice<R> map(Function<? super T, ? extends R> mapper) {
        return new CursorSlice<>(content.stream().<R>map(mapper).toList(), nextCursor);
    }
}
