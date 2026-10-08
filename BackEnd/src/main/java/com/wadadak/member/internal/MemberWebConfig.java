package com.wadadak.member.internal;

import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
class MemberWebConfig {

    /** 로그인·가입·갱신은 토큰 없이 호출한다. 공통 체인보다 먼저 적용한다. */
    @Bean
    @Order(1)
    SecurityFilterChain memberAuthFilterChain(HttpSecurity http) {
        return http
                .securityMatcher("/api/v1/members/auth/**")
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth.anyRequest().permitAll())
                .build();
    }

    @Bean
    GroupedOpenApi memberApiGroup() {
        return GroupedOpenApi.builder().group("member").pathsToMatch("/api/v1/members/**").build();
    }
}
