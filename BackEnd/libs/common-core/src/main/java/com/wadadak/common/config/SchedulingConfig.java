package com.wadadak.common.config;

import net.javacrumbs.shedlock.core.LockProvider;
import net.javacrumbs.shedlock.provider.jdbctemplate.JdbcTemplateLockProvider;
import net.javacrumbs.shedlock.spring.annotation.EnableSchedulerLock;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;

import javax.sql.DataSource;

/**
 * 스케줄 작업은 {@code @SchedulerLock}으로 인스턴스 하나에서만 실행한다(개발 정책 8.1).
 * 잠금 테이블은 서비스마다 자기 스키마에 둔다({@code app.common.shedlock.table}, MSA 분리 3단계 개발 정책 11.3).
 */
@Configuration
@EnableScheduling
@EnableSchedulerLock(defaultLockAtMostFor = "PT10M")
public class SchedulingConfig {

    @Bean
    LockProvider lockProvider(DataSource dataSource,
                              @Value("${app.common.shedlock.table:common.shedlock}") String table) {
        return new JdbcTemplateLockProvider(JdbcTemplateLockProvider.Configuration.builder()
                .withJdbcTemplate(new JdbcTemplate(dataSource))
                .withTableName(table)
                .usingDbTime()
                .build());
    }
}
