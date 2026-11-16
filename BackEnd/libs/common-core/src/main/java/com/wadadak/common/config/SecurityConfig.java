package com.wadadak.common.config;

import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.exception.ErrorCode;
import com.wadadak.common.response.ApiResult;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.ProviderManager;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.AccessDeniedHandler;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;

/**
 * JWT(RS256) 검증만 한다. 발급은 member가 개인키로 한다(개발 정책 7장).
 * 공개키는 {@code spring.security.oauth2.resourceserver.jwt.public-key-location}으로 받는다.
 * <p>
 * 운영자 API({@code /api/v1/admin/**})만 따로, 서버 환경 변수의 공용 운영자 계정 하나로 HTTP Basic 로그인한다(2026-11-12 결정).
 */
@Configuration
public class SecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http, JsonMapper jsonMapper) {
        AuthenticationEntryPoint unauthorized = (request, response, e) ->
                write(response, jsonMapper, CommonErrorCode.UNAUTHORIZED);
        AccessDeniedHandler forbidden = (request, response, e) ->
                write(response, jsonMapper, CommonErrorCode.FORBIDDEN);

        return http
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/error", "/actuator/health", "/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html")
                        .permitAll()
                        // 운영자 웹 페이지(정적 HTML) 자체는 누구나 받는다. 데이터는 /api/v1/admin/** 가 운영자 계정으로 막는다
                        .requestMatchers("/admin", "/admin/**")
                        .permitAll()
                        .anyRequest().authenticated())
                .oauth2ResourceServer(oauth2 -> oauth2
                        .jwt(Customizer.withDefaults())
                        .authenticationEntryPoint(unauthorized))
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint(unauthorized)
                        .accessDeniedHandler(forbidden))
                .build();
    }

    /**
     * 운영자 API. 요청마다 {@code Authorization: Basic …}(아이디:비밀번호)을 확인한다. 회원 JWT로는 들어올 수 없다.
     * 계정은 {@code app.admin.username} · {@code app.admin.password}(환경 변수 ADMIN_USERNAME · ADMIN_PASSWORD)이고,
     * 비어 있으면 운영자 계정이 없어서 모두 401이다.
     * <p>
     * [@Order] 체인이 여러 개면 번호가 작은 것부터 URL을 맞춰 본다. 이 체인은 {@code /api/v1/admin/**}만 맡고,
     * 나머지는 위의 JWT 체인(번호 없음 = 맨 뒤)이 맡는다.
     * <p>
     * 401 응답에 {@code WWW-Authenticate} 헤더를 넣지 않는다. 넣으면 운영자 웹이 fetch할 때 브라우저가 자체 로그인 창을 띄운다.
     */
    @Bean
    @Order(2)
    SecurityFilterChain adminSecurityFilterChain(HttpSecurity http, JsonMapper jsonMapper,
                                                 @Value("${app.admin.username:}") String username,
                                                 @Value("${app.admin.password:}") String password) {
        AuthenticationEntryPoint unauthorized = (request, response, e) ->
                write(response, jsonMapper, CommonErrorCode.UNAUTHORIZED);
        AccessDeniedHandler forbidden = (request, response, e) ->
                write(response, jsonMapper, CommonErrorCode.FORBIDDEN);
        PasswordEncoder encoder = PasswordEncoderFactories.createDelegatingPasswordEncoder();
        // 비밀번호는 서버가 뜰 때 한 번 해시해서 메모리에만 둔다
        InMemoryUserDetailsManager admins = username.isBlank() || password.isBlank()
                ? new InMemoryUserDetailsManager()
                : new InMemoryUserDetailsManager(User.withUsername(username).password(encoder.encode(password)).roles("ADMIN").build());
        DaoAuthenticationProvider provider = new DaoAuthenticationProvider(admins);
        provider.setPasswordEncoder(encoder);

        return http
                .securityMatcher("/api/v1/admin/**")
                .csrf(AbstractHttpConfigurer::disable) // 쿠키를 쓰지 않아서 CSRF 위험이 없다
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authenticationManager(new ProviderManager(provider))
                .authorizeHttpRequests(auth -> auth.anyRequest().hasRole("ADMIN"))
                .httpBasic(basic -> basic.authenticationEntryPoint(unauthorized))
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint(unauthorized)
                        .accessDeniedHandler(forbidden))
                .build();
    }

    private static void write(HttpServletResponse response, JsonMapper jsonMapper, ErrorCode errorCode) throws IOException {
        response.setStatus(errorCode.getStatus().value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        jsonMapper.writeValue(response.getOutputStream(), ApiResult.error(errorCode));
    }
}
