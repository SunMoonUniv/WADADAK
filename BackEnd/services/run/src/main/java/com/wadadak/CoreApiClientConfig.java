package com.wadadak;

import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseApiHttpClient;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingApiHttpClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/**
 * run이 쓰는 {@link CourseApi} · {@link RankingApi}를 core 내부 API(/internal/v1/**)로 부른다(MSA 분리 2단계, 개발 정책 11.3).
 * 모놀리스에서 course · ranking 모듈이 주던 빈 자리다. 모듈 밖(애플리케이션 루트)에 두어 run 모듈 테스트에는 뜨지 않는다.
 */
@Configuration(proxyBeanMethods = false)
class CoreApiClientConfig {

    @Bean
    CourseApi courseApi(@Value("${app.run.core-api.base-url}") String baseUrl,
                        @Value("${app.run.core-api.timeout}") Duration timeout) {
        return new CourseApiHttpClient(baseUrl, timeout);
    }

    @Bean
    RankingApi rankingApi(@Value("${app.run.core-api.base-url}") String baseUrl,
                          @Value("${app.run.core-api.timeout}") Duration timeout) {
        return new RankingApiHttpClient(baseUrl, timeout);
    }
}
