package com.wadadak.common.stub;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.support.StaticListableBeanFactory;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class StubGuardTest {

    @Test
    void failsWhenStubBeanExists() {
        var beans = new StaticListableBeanFactory(Map.of("stub", new StubImplementation() {
        }));

        assertThatThrownBy(() -> new StubGuard(beans.getBeanProvider(StubImplementation.class)))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void passesWithoutStubs() {
        var beans = new StaticListableBeanFactory();

        assertThatCode(() -> new StubGuard(beans.getBeanProvider(StubImplementation.class)))
                .doesNotThrowAnyException();
    }
}
