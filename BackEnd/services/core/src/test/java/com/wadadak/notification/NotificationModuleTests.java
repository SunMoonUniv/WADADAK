package com.wadadak.notification;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.notification.internal.push.PushSender;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Import;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * notification 단독 기동(다른 도메인 모듈 없이, 가짜로 채울 다른 모듈 API도 없다). 분리 가능성의 직접 증거다(개발 정책 10.6).
 * notification은 이벤트만 받고 아무 모듈도 호출하지 않는다.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class NotificationModuleTests {

    @Autowired
    ApplicationContext context;

    @Autowired
    PushSender pushSender;

    @Test
    void startsAloneWithTheLocalPushSender() {
        // 시험에는 FCM 키가 없어 로그만 남기는 발송이 뜬다
        assertThat(pushSender.getClass().getSimpleName()).isEqualTo("LoggingPushSender");
        // 시험은 발송 작업을 끄고 직접 부른다
        assertThat(context.getBeanNamesForType(Object.class))
                .noneMatch(name -> name.equalsIgnoreCase("pushDispatchScheduler"));
    }
}
