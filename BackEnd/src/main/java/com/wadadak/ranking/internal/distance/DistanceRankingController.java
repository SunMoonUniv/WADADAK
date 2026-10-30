package com.wadadak.ranking.internal.distance;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
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
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/rankings")
@RequiredArgsConstructor
class DistanceRankingController {

    private static final String PERIOD = "ALL 누적, MONTH 이번 달(1일 00:00부터), WEEK 이번 주(월요일 00:00부터). 기록 등록 시각(Asia/Seoul) 기준";
    private static final String REGION = "시·군·구 법정동 코드. 비우면 요청자의 이번 주 활동 지역";
    static final int MAX_MEMBER_IDS = 100;

    private final DistanceRankingReader reader;
    private final RegionDirectory regions;

    @Operation(summary = "누적 거리 랭킹 (E1 전체 랭킹 탭)",
            description = "참여 러너 수·내 순위·시상대 1~3위. 4위부터는 nextCursor로 목록 API를 부른다. "
                    + "오늘 자정(Asia/Seoul) 전에 등록된 기록으로 계산하고 내 순위·거리도 같은 기준이다(calculatedAt). "
                    + "자정 뒤에 지운 기록·탈퇴·내 정보 비공개는 바로 빠진다. "
                    + "자유 러닝·미완주·코스 밖의 정상 측정 거리도 포함하고, 내 정보 비공개 회원은 빠진다. "
                    + "me.status: RANKED / NO_RECORD 그 기간 기록 없음 / PRIVATE 내 정보 비공개(순위 대신 `비공개 중`). "
                    + "me.nickname·me.profileImageUrl은 내 행의 `나 (닉네임)`·사진용이고 상태와 관계없이 채운다(조회 실패 시 null). "
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
                    + "가입 때 지역은 바로, 바꾼 지역은 다음 주부터 들어간다(이번 주는 바꾸기 전 지역). "
                    + "상위 5줄을 주고 6위부터는 nextCursor로 목록 API를 부른다. "
                    + "me.status: RANKED(lastWeekRank는 \"지난주 n위\", 지난주 이 지역 마지막 순위) / NO_RECORD / PRIVATE / "
                    + "OTHER_REGION 내 활동 지역이 아닌 지역. me.nickname·me.profileImageUrl은 전체 랭킹과 같다. "
                    + "없는 지역이거나 시·군·구가 아닌 코드는 RANKING-002(404). regionCode를 비웠는데 내 활동 지역을 아직 받지 못했어도(가입 직후 잠깐) 같다.")
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

    @Operation(summary = "회원별 이번 주 거리 (G7 러너 검색)",
            description = "러너 검색 결과의 \"주 32 km\". memberIds(최대 100명)마다 이번 주 거리(m 정수)를 하나씩 준다. "
                    + "전체 랭킹 me.thisWeekDistanceMeters와 같은 값으로, 이번 주 월요일 00:00부터 오늘 자정(Asia/Seoul) 전에 "
                    + "등록된 기록이다. 자유 러닝 · 미완주 거리도 포함한다. 기록이 없으면 0, 내 정보 비공개 회원은 null"
                    + "(요청자 본인은 비공개여도 준다). 같은 ID는 한 번만 준다. 100명을 넘거나 잘못된 ID는 COMMON-001.")
    @GetMapping("/distance/members")
    ApiResult<List<MemberWeekDistance>> weekDistances(
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(description = "회원 ID. 쉼표로 잇거나 같은 이름으로 여러 번 보낸다") @RequestParam List<UUID> memberIds) {
        // 쉼표 사이가 비어 있으면(`a,,b`) 스프링이 null로 바꿔 넘긴다
        if (memberIds.contains(null)) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "memberIds: 빈 ID가 있습니다.");
        }
        Set<UUID> ids = new LinkedHashSet<>(memberIds);
        if (ids.size() > MAX_MEMBER_IDS) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "memberIds: 최대 " + MAX_MEMBER_IDS + "명입니다.");
        }
        return ApiResult.success(reader.weekDistances(ids, memberId(jwt)));
    }

    @Operation(summary = "회원 누적 거리 · 러닝 수 (I3)",
            description = "다른 러너 프로필의 `총 거리` · `러닝`. 전체 랭킹 누적(ALL)과 같은 기준으로 오늘 자정(Asia/Seoul) 전에 등록된 "
                    + "기록 전체다. 자유 러닝 · 미완주 기록도 센다. 기록이 없으면 0, 내 정보 비공개 회원은 둘 다 null"
                    + "(요청자 본인은 비공개여도 준다). 거리는 m 정수. 잘못된 ID는 COMMON-001.")
    @GetMapping("/distance/members/{memberId}")
    ApiResult<MemberDistanceTotal> memberTotal(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID memberId) {
        return ApiResult.success(reader.memberTotal(memberId, memberId(jwt)));
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
