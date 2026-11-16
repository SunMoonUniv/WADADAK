package com.wadadak.common.paging;

import java.util.List;

/**
 * 번호 페이징 응답. 운영자 웹 표 아래의 1 · 2 · 3 … 페이지 버튼에 쓴다. 앱은 커서 페이징({@link CursorSlice})을 쓴다.
 *
 * @param totalCount 조건에 맞는 전체 개수. 웹이 마지막 페이지 번호와 "1–20 / 1,284개"를 계산한다
 */
public record NumberedPage<T>(List<T> content, long totalCount) {
}
