package com.wadadak.common.config;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.exception.ErrorCode;
import com.wadadak.common.response.ApiResult;
import com.wadadak.common.response.ResultType;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpRequest;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.client.ClientHttpRequestExecution;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.web.client.RestClient;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.io.IOException;
import java.time.Duration;
import java.util.stream.Stream;

/**
 * 서비스 사이 내부 API({@code /internal/v1/**}) 호출 공통(MSA 분리 2단계, 개발 정책 11.3). 모듈의 HTTP 구현체가 쓴다.
 * <ul>
 *   <li>지금 처리 중인 앱 요청의 {@code Authorization}을 그대로 넘긴다. 내부 API도 같은 JWT 검증을 받는다.
 *       서비스 사이 호출은 모두 사용자 요청 안에서 한다(개발 정책 4.4). 요청 밖에서 부르면 토큰이 없어 COMMON-002다.</li>
 *   <li>오류 응답도 {@link ApiResult} 본문으로 읽어 같은 {@link AppException}으로 되돌린다.
 *       호출 쪽 코드는 모놀리스 안에서 부를 때와 같은 예외를 받는다.</li>
 * </ul>
 */
public final class InternalApiClient {

    private InternalApiClient() {
    }

    public static RestClient restClient(String baseUrl, Duration timeout) {
        return RestClient.builder()
                .baseUrl(baseUrl)
                .requestFactory(HttpTimeouts.requestFactory(timeout))
                .requestInterceptor(InternalApiClient::forwardAuthorization)
                // 오류여도 예외를 던지지 않고 본문(ApiResult)을 읽게 둔다. 판단은 unwrap이 한다
                .defaultStatusHandler(HttpStatusCode::isError, (request, response) -> {
                })
                .build();
    }

    /**
     * 성공이면 {@code data}, 실패면 코드에 맞는 {@link AppException}. 모르는 코드는 COMMON-006(서버 오류)으로 바꾼다.
     *
     * @param known 호출 대상 모듈의 에러 코드({@code CourseErrorCode.values()} 등). 공통 코드는 따로 넘기지 않아도 된다
     */
    public static <T> T unwrap(ApiResult<T> result, ErrorCode... known) {
        if (result != null && result.result() == ResultType.SUCCESS) {
            return result.data();
        }
        if (result == null) {
            throw new AppException(CommonErrorCode.INTERNAL_ERROR);
        }
        ErrorCode code = Stream.concat(Stream.of(known), Stream.of(CommonErrorCode.values()))
                .filter(candidate -> candidate.getCode().equals(result.code()))
                .findFirst().orElse(CommonErrorCode.INTERNAL_ERROR);
        throw new AppException(code, result.message() != null ? result.message() : code.getMessage());
    }

    private static ClientHttpResponse forwardAuthorization(HttpRequest request, byte[] body, ClientHttpRequestExecution execution)
            throws IOException {
        if (RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes attributes) {
            String authorization = attributes.getRequest().getHeader(HttpHeaders.AUTHORIZATION);
            if (authorization != null) {
                request.getHeaders().set(HttpHeaders.AUTHORIZATION, authorization);
            }
        }
        return execution.execute(request, body);
    }
}
