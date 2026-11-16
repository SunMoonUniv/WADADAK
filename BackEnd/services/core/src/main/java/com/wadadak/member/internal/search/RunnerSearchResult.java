package com.wadadak.member.internal.search;

import com.wadadak.common.region.Region;
import com.wadadak.member.internal.account.RunningExperience;

import java.util.List;
import java.util.UUID;

/**
 * 러너 검색 결과 한 쪽(G7).
 *
 * @param totalCount 검색어에 걸린 러너 수(SEA-02). 쪽마다 같은 값을 다시 센다
 * @param nextCursor 다음 쪽을 요청할 때 {@code cursor}에 넣는 값. 마지막 쪽이면 null
 */
record RunnerSearchResult(int totalCount, List<Runner> content, String nextCursor) {

    /**
     * 러너 한 줄. 누르면 {@code memberId}로 I3(다른 러너 프로필)에 간다.
     *
     * @param profileImageUrl 프로필 사진이 없으면 {@code null}
     * @param region          활동 지역(시·군·구). 코드가 지역 목록에서 사라졌으면 {@code null}
     * @param mine            요청자 본인이면 {@code true}. 앱은 I3 대신 MY로 보낸다
     */
    record Runner(UUID memberId, String nickname, String profileImageUrl, Region region,
                  RunningExperience runningExperience, boolean mine) {
    }
}
