package com.wadadak.notification.internal;

import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Swagger(API 문서)에서 notification API만 따로 모아 보이게 한다. 나중에 notification을 서비스로 떼어내면
 * 이 그룹이 그대로 그 서비스의 명세가 된다(개발 정책 7장).
 */
@Configuration
class NotificationWebConfig {

    @Bean
    GroupedOpenApi notificationApiGroup() {
        return GroupedOpenApi.builder().group("notification").pathsToMatch("/api/v1/notifications/**").build();
    }
}
