package com.wadadak.ranking.internal.distance;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.region.Region;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.response.ApiResult;
import com.wadadak.ranking.RankingErrorCode;
import com.wadadak.ranking.RankingPeriod;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/rankings")
@RequiredArgsConstructor
class DistanceRankingController {

    private static final int REGION_SEARCH_LIMIT = 20;
    private static final String PERIOD = "ALL 누적, MONTH 이번 달(1일 00:00부터), WEEK 이번 주(월요일 00:00부터). 기록 등록 시각(Asia/Seoul) 기준";
    private static final String REGION = "시·군·구 법정동 코드. 비우면 요청자의 이번 주 활동 지역";

    private final DistanceRankingReader reader;
    private final RegionDirectory regions;

    @Operation(summary = "누적 거리 랭킹 (E1 전체 랭킹 탭)",
            description = "참여 러너 수·내 순위·시상대 1~3위. 4위부터는 nextCursor로 목록 API를 부른다. "
                    + "매일 자정(Asia/Seoul)에 계산한 값이고 내 순위·거리도 같은 시점 기준이다(calculatedAt). "
                    + "자유 러닝·미완주·코스 밖의 정상 측정 거리도 포함하고, 내 정보 비공개 회원은 빠진다. "
                    + "me.status: RANKED / NO_RECORD 그 기간 기록 없음 / PRIVATE 내 정보 비공개(순위 대신 `비공개 중`). "
                    + "me.thisWeekDistanceMeters는 \"이번 주 +n km\", topPercent는 순위 ÷ 참여 수 × 100 올림. 거리는 m 단위 정수.")
    @GetMapping("/distance")
    ApiResult<DistanceRankingSummary> summary(
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(description = PERIOD) @RequestParam(defaultValue = "ALL") RankingPeriod period) {
        return ApiResult.success(reader.summary(period, memberId(jwt)));
    }

    @Operation(summary = "누적 거리 랭킹 목록 (E1 전체 순위)",
            description = "거리 순 커서 페이징. 같은 거리면 같은 순위(1·2·2·4). weeklyAverageMeters는 \"주 평균\"(누적 거리 ÷ 첫 기록 주부터 이번 주까지 주 수). "
                    + "잘못된 cursor·size는 COMMON-001.")
    @GetMapping("/distance/entries")
    ApiResult<CursorSlice<DistanceRankingEntry>> entries(
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(description = PERIOD) @RequestParam(defaultValue = "ALL") RankingPeriod period,
            @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(reader.entries(period, memberId(jwt), page));
    }

    @Operation(summary = "지역 주간 랭킹 (E1 지역 탭, I5)",
            description = "회원 활동 지역(시·군·구)이 같은 회원끼리 이번 주 거리로 순위를 매긴다. 매일 자정에 계산하고 월요일 00:00에 새로 시작한다. "
                    + "활동 지역을 바꾼 회원은 다음 주부터 새 지역에 들어간다. 상위 5줄을 주고 6위부터는 nextCursor로 목록 API를 부른다. "
                    + "me.status: RANKED(lastWeekRank는 \"지난주 n위\") / NO_RECORD / PRIVATE / OTHER_REGION 내 활동 지역이 아닌 지역. "
                    + "없는 지역이거나 시·군·구가 아닌 코드는 RANKING-002(404). "
                    + "스텁: 요청자의 활동 지역은 서울 성북구(1129000000)로 둔다.")
    @GetMapping("/distance/regions/weekly")
    ApiResult<RegionWeeklyRanking> regionWeekly(
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(description = REGION) @RequestParam(required = false) String regionCode) {
        return ApiResult.success(reader.regionWeekly(region(regionCode), memberId(jwt)));
    }

    @Operation(summary = "지역 주간 랭킹 목록 (I5 전체 순위)", description = "거리 순 커서 페이징. 지역 규칙은 지역 주간 랭킹과 같다.")
    @GetMapping("/distance/regions/weekly/entries")
    ApiResult<CursorSlice<DistanceRankingEntry>> regionWeeklyEntries(
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(description = REGION) @RequestParam(required = false) String regionCode,
            @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(reader.regionWeeklyEntries(region(regionCode), memberId(jwt), page));
    }

    @Operation(summary = "시·군·구 검색 (I6 지역 선택)",
            description = "이름이나 상위 구역 이름에 검색어가 들어간 시·군·구를 최대 20개. 이름이 정확히 같은 지역이 먼저 온다. "
                    + "빈 검색어나 20자 초과는 COMMON-001.")
    @GetMapping("/regions")
    ApiResult<List<Region>> searchRegions(@RequestParam @NotBlank @Size(max = 20) String query) {
        return ApiResult.success(regions.searchSigungu(query, REGION_SEARCH_LIMIT));
    }

    private Region region(String regionCode) {
        if (regionCode == null) {
            return null;
        }
        return regions.findSigungu(regionCode).orElseThrow(() -> new AppException(RankingErrorCode.REGION_NOT_FOUND));
    }

    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
