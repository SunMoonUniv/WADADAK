package com.wadadak.course.internal;

import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class CourseWebConfig {

    @Bean
    GroupedOpenApi courseApiGroup() {
        return GroupedOpenApi.builder().group("course").pathsToMatch("/api/v1/courses/**").build();
    }
}
