package com.wadadak.common.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 공통 OpenAPI 정보와 JWT 인증 스키마. 그룹({@code GroupedOpenApi})은 모듈마다 자기 {@code internal}에 둔다.
 * 그룹 하나 = URL prefix 하나 = 분리 후 서비스 하나(개발 정책 7장).
 */
@Configuration
public class SwaggerConfig {

    private static final String BEARER = "bearer-jwt";

    @Bean
    OpenAPI openAPI() {
        return new OpenAPI()
                .info(new Info().title("WADADAK API").version("v1"))
                .components(new Components().addSecuritySchemes(BEARER, new SecurityScheme()
                        .type(SecurityScheme.Type.HTTP).scheme("bearer").bearerFormat("JWT")))
                .addSecurityItem(new SecurityRequirement().addList(BEARER));
    }
}
