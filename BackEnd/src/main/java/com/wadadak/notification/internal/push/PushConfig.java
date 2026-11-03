package com.wadadak.notification.internal.push;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ResourceLoader;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;

/**
 * 푸시 발송 구현을 고른다. FCM 서비스 계정 키 위치가 있으면 FCM, 없으면 로그만 남기는 가짜 발송이다.
 *
 * <p>키 위치는 {@code file:/경로/key.json} 또는 {@code base64:…}(배포 비밀값을 그대로, JWT 키와 같은 방식)다.
 * 키가 없어도 서버는 뜬다. 알림은 만들어지고 발송 기록도 남지만 기기에는 가지 않는다(경고 로그로 알린다).
 */
@Slf4j
@Configuration
class PushConfig {

    @Bean
    PushSender pushSender(@Value("${app.notification.fcm.credentials-location:}") String credentialsLocation,
                          ResourceLoader resources, JsonMapper json) throws IOException {
        if (credentialsLocation.isBlank()) {
            log.warn("FCM 서비스 계정 키가 없어 푸시를 보내지 않고 로그로만 남긴다(app.notification.fcm.credentials-location)");
            return new LoggingPushSender();
        }
        PushSender sender = FcmPushSender.fromServiceAccount(resources.getResource(credentialsLocation), json);
        log.info("푸시를 FCM으로 보낸다");
        return sender;
    }
}
