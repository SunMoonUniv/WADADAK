package com.wadadak.run.internal;

import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class RunWebConfig {
    @Bean GroupedOpenApi runApiGroup() {
        return GroupedOpenApi.builder().group("run").pathsToMatch("/api/v1/runs/**").build();
    }
}
