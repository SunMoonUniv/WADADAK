package com.wadadak.course;

import com.wadadak.common.config.InternalApiClient;
import com.wadadak.common.response.ApiResult;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.web.client.RestClient;

import java.time.Duration;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * {@link CourseApi}의 HTTP 구현체(MSA 분리 2단계, 개발 정책 11.3). 분리 뒤 run 서비스가 core의 내부 API를 부른다.
 * 모놀리스에서는 빈으로 등록하지 않는다(계약 테스트만 직접 만든다). 3단계에서 계약 jar {@code course-api}로 옮긴다.
 */
public final class CourseApiHttpClient implements CourseApi {

    private static final ParameterizedTypeReference<ApiResult<CourseRouteSnapshot>> ROUTE = new ParameterizedTypeReference<>() {
    };

    private final RestClient rest;

    /** @param baseUrl core 서비스 주소(예: {@code http://core:8080}) */
    public CourseApiHttpClient(String baseUrl, Duration timeout) {
        this.rest = InternalApiClient.restClient(baseUrl, timeout);
    }

    @Override
    public CourseRouteSnapshot getRouteForRun(UUID courseId) {
        return InternalApiClient.unwrap(rest.get().uri("/internal/v1/courses/{courseId}/route", courseId)
                .retrieve().body(ROUTE), CourseErrorCode.values());
    }

    /** review 전용이라 서비스 사이 호출이 아니다. run은 부르지 않으므로 내부 API를 열지 않았다 */
    @Override
    public Map<UUID, String> getNames(Set<UUID> courseIds) {
        throw new UnsupportedOperationException("코스 이름 일괄 조회는 core 안(review)에서만 쓴다");
    }
}
