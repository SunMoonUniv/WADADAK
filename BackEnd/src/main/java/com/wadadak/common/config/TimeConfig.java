package com.wadadak.common.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.time.ZoneId;

/**
 * 기간 계산(만료일·이번 주·이번 달)은 Asia/Seoul 기준이다. 테스트에서는 고정 Clock으로 바꾼다.
 */
@Configuration
public class TimeConfig {

    public static final ZoneId SEOUL = ZoneId.of("Asia/Seoul");

    @Bean
    Clock clock() {
        return Clock.system(SEOUL);
    }
}
