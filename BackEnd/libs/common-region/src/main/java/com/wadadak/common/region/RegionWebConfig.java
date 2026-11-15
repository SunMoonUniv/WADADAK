package com.wadadak.common.region;

import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
class RegionWebConfig {

    /**
     * 지역 검색은 토큰 없이 호출한다(가입 전 화면에서도 쓴다). 토큰이 붙어 와도 검증하지 않아, 만료된 토큰으로 401이 나지 않는다.
     * 공통 체인보다 먼저 적용한다.
     */
    @Bean
    @Order(2)
    SecurityFilterChain regionFilterChain(HttpSecurity http) {
        return http
                .securityMatcher("/api/v1/regions/**")
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth.anyRequest().permitAll())
                .build();
    }

    @Bean
    GroupedOpenApi regionApiGroup() {
        return GroupedOpenApi.builder().group("region").pathsToMatch("/api/v1/regions/**").build();
    }
}
