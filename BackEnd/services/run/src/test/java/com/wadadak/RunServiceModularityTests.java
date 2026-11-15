package com.wadadak;

import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;

/**
 * run 서비스의 모듈 경계 검사. course · ranking은 계약 jar의 공개 타입만 있다(개발 정책 11.3 3단계).
 */
class RunServiceModularityTests {

    @Test
    void verify() {
        ApplicationModules.of(RunServiceApplication.class).verify();
    }
}
