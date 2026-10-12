package com.wadadak.ranking.internal.course;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.response.ApiResult;
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

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/rankings/courses/{courseId}")
@RequiredArgsConstructor
class CourseRankingController {

    private static final String PERIOD = "ALL 전체, MONTH 이번 달(1일 00:00부터), WEEK 이번 주(월요일 00:00부터). 기록 등록 시각(Asia/Seoul) 기준";

    private final CourseRankingReader reader;

    @Operation(summary = "코스 랭킹 요약 (B9)",
            description = "참여 러너 수·랭킹 평균 총 소요시간·내 순위·상위 5줄·첫 공개 고스트. G3 상단과 B1·B8 고스트 대결 버튼(period=ALL)에도 쓴다. "
                    + "내 정보 비공개 회원은 참여 수·평균·순위·목록에서 모두 빠진다. 기록이 없거나 숨김·삭제된 코스는 참여 0명이다. "
                    + "me.status: RANKED 순위 있음 / NO_RECORD 그 기간 완주 기록 없음 / PRIVATE 내 정보 비공개(순위 대신 `비공개 중`). "
                    + "topPercent = 순위 ÷ 참여 수 × 100 올림. 시간은 정수 초, 페이스는 km당 초(반올림). "
                    + "top[0]이 1위다. ghost가 null이면 고스트 대결 버튼을 끈다. "
                    + "스텁 확인용 courseId: 00000000-0000-0000-0000-000000000001 기록 없음, …0002 요청자 비공개.")
    @GetMapping
    ApiResult<CourseRankingSummary> summary(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID courseId,
            @Parameter(description = PERIOD) @RequestParam(defaultValue = "ALL") RankingPeriod period) {
        return ApiResult.success(reader.summary(courseId, period, UUID.fromString(jwt.getSubject())));
    }

    @Operation(summary = "코스 전체 순위 (G3)",
            description = "순위순 커서 페이징. 화면 진입·기간 변경·새로고침 때는 cursor 없이 첫 페이지부터 다시 조회한다. "
                    + "rank는 공동순위면 같은 값이고 다음 순위는 그 인원만큼 건너뛴다(1·2·2·4). mine=true인 내 행은 눌러도 프로필로 가지 않는다. "
                    + "잘못된 cursor·size는 COMMON-001.")
    @GetMapping("/entries")
    ApiResult<CursorSlice<CourseRankingEntry>> entries(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID courseId,
            @Parameter(description = PERIOD) @RequestParam(defaultValue = "ALL") RankingPeriod period,
            @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(reader.entries(courseId, period, UUID.fromString(jwt.getSubject()), page));
    }
}
