package com.wadadak.ranking.internal;

import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class RankingWebConfig {

    @Bean
    GroupedOpenApi rankingApiGroup() {
        return GroupedOpenApi.builder().group("ranking").pathsToMatch("/api/v1/rankings/**").build();
    }
}
