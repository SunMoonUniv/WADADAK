package com.wadadak.ranking.internal.course;

import com.wadadak.common.response.ApiResult;
import com.wadadak.ranking.GhostCandidate;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingPeriod;
import io.swagger.v3.oas.annotations.Hidden;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * 서비스 사이 내부 API(MSA 분리 2단계, 개발 정책 11.3). 분리 뒤 run이 {@code RankingApiHttpClient}로 부른다.
 * 앱용이 아니라 Swagger에서 숨긴다. 켜는 값은 {@code app.common.internal-api.enabled}.
 */
@Hidden
@RestController
@RequestMapping("/internal/v1/rankings")
@ConditionalOnProperty(name = "app.common.internal-api.enabled", havingValue = "true")
@RequiredArgsConstructor
class RankingInternalController {

    private final RankingApi rankingApi;

    /** {@link RankingApi#findPublicGhostCandidate}. 후보가 아니면 {@code data: null}(오류가 아니다) */
    @GetMapping("/courses/{courseId}/public-ghosts/{runRecordId}")
    ApiResult<GhostCandidate> publicGhost(@PathVariable UUID courseId, @PathVariable UUID runRecordId,
                                          @RequestParam RankingPeriod period, @RequestParam UUID requesterId) {
        return ApiResult.success(rankingApi.findPublicGhostCandidate(courseId, period, requesterId, runRecordId).orElse(null));
    }
}
