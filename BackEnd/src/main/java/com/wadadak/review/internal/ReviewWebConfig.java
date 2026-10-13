package com.wadadak.review.internal;

import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Swagger(API 문서)에서 review API만 따로 모아 보이게 한다. 모듈마다 그룹을 나눠서, 나중에 서비스로 떼어내도
 * 그 서비스의 명세가 그대로 이 그룹이 된다(개발 정책 7장).
 */
@Configuration // 스프링 설정 클래스. 안의 @Bean 메서드가 돌려준 객체를 스프링이 관리한다
class ReviewWebConfig {

    @Bean
    GroupedOpenApi reviewApiGroup() {
        return GroupedOpenApi.builder().group("review").pathsToMatch("/api/v1/reviews/**").build();
    }
}
