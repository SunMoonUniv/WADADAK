package com.wadadak.common.stub;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * 운영에서 스텁이 켜진 채 기동되는 것을 막는다({@code app.stub.*: true} 실수 방지).
 */
@Component
@Profile("prod")
public class StubGuard {

    public StubGuard(ObjectProvider<StubImplementation> stubs) {
        List<String> names = stubs.stream().map(stub -> stub.getClass().getName()).toList();
        if (!names.isEmpty()) {
            throw new IllegalStateException("prod 프로필에서 스텁이 활성화되어 있습니다: " + names);
        }
    }
}
