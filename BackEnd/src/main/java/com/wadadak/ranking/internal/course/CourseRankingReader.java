package com.wadadak.ranking.internal.course;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.ranking.RankingPeriod;

import java.util.UUID;

/**
 * 코스 랭킹 조회(B9·G3). {@code app.stub.ranking: true}면 스텁이 대신한다(개발 정책 3.2).
 * 숨김·삭제된 코스나 기록이 없는 코스는 참여 0명으로 돌려준다.
 */
interface CourseRankingReader {

    CourseRankingSummary summary(UUID courseId, RankingPeriod period, UUID requesterId);

    /** 순위순. 같은 순위끼리의 순서는 페이지를 넘겨도 바뀌지 않는다. */
    CursorSlice<CourseRankingEntry> entries(UUID courseId, RankingPeriod period, UUID requesterId, Cursorable page);
}
