package com.wadadak;

import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;

/**
 * 모듈 경계 검사(다른 모듈 internal import, 순환 의존). CI에서 실패하면 머지하지 않는다(개발 정책 3.1).
 */
class ModularityTests {

    @Test
    void verify() {
        ApplicationModules.of(WadadakApplication.class).verify();
    }
}
