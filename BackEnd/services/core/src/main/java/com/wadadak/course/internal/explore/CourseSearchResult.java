package com.wadadak.course.internal.explore;

import java.util.List;

/**
 * 코스 검색 결과 한 쪽(G1). 카드는 코스 목록과 같다.
 *
 * @param totalCount 검색어에 걸린 코스 수(`코스 검색 결과 N`, SEA-02). 쪽마다 같은 값을 다시 센다
 * @param nextCursor 다음 쪽을 요청할 때 {@code cursor}에 넣는 값. 마지막 쪽이면 null
 */
record CourseSearchResult(int totalCount, List<CourseListItem> content, String nextCursor) {
}
