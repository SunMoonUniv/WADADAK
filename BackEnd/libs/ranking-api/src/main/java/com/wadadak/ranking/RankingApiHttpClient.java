package com.wadadak.ranking;

import com.wadadak.common.config.InternalApiClient;
import com.wadadak.common.response.ApiResult;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.web.client.RestClient;

import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * {@link RankingApi}의 HTTP 구현체(MSA 분리 2단계, 개발 정책 11.3). 분리 뒤 run 서비스가 core의 내부 API를 부른다.
 * 모놀리스에서는 빈으로 등록하지 않는다(계약 테스트만 직접 만든다). 3단계에서 계약 jar {@code ranking-api}로 옮긴다.
 */
public final class RankingApiHttpClient implements RankingApi {

    private static final ParameterizedTypeReference<ApiResult<GhostCandidate>> CANDIDATE = new ParameterizedTypeReference<>() {
    };

    private final RestClient rest;

    /** @param baseUrl core 서비스 주소(예: {@code http://core:8080}) */
    public RankingApiHttpClient(String baseUrl, Duration timeout) {
        this.rest = InternalApiClient.restClient(baseUrl, timeout);
    }

    /** run은 부르지 않는다. 그래서 내부 API를 열지 않았다 */
    @Override
    public List<GhostCandidate> getPublicGhostCandidates(UUID courseId, RankingPeriod period, UUID requesterId, int limit) {
        throw new UnsupportedOperationException("공개 고스트 후보 목록은 서비스 사이에서 쓰지 않는다");
    }

    @Override
    public Optional<GhostCandidate> findPublicGhostCandidate(UUID courseId, RankingPeriod period, UUID requesterId,
                                                             UUID runRecordId) {
        return Optional.ofNullable(InternalApiClient.unwrap(rest.get()
                .uri("/internal/v1/rankings/courses/{courseId}/public-ghosts/{runRecordId}?period={period}&requesterId={requesterId}",
                        courseId, runRecordId, period, requesterId)
                .retrieve().body(CANDIDATE), RankingErrorCode.values()));
    }
}
