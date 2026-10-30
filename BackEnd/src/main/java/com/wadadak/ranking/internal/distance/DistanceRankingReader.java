package com.wadadak.ranking.internal.distance;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.region.Region;
import com.wadadak.ranking.RankingPeriod;

import java.util.List;
import java.util.Set;
import java.util.UUID;

/** 누적 거리 랭킹 조회(F12). 순위는 거리 순, 같은 순위 안에서는 순서가 페이지를 넘겨도 바뀌지 않는다. */
interface DistanceRankingReader {

    DistanceRankingSummary summary(RankingPeriod period, UUID requesterId);

    CursorSlice<DistanceRankingEntry> entries(RankingPeriod period, UUID requesterId, Cursorable page);

    /** @param region {@code null}이면 요청자의 이번 주 활동 지역 */
    RegionWeeklyRanking regionWeekly(Region region, UUID requesterId);

    /** @param region {@code null}이면 요청자의 이번 주 활동 지역 */
    CursorSlice<DistanceRankingEntry> regionWeeklyEntries(Region region, UUID requesterId, Cursorable page);

    /** 회원마다 이번 주 거리(G7). 개수 제한은 컨트롤러가 본다 */
    List<MemberWeekDistance> weekDistances(Set<UUID> memberIds, UUID requesterId);
}
