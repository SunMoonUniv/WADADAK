package com.wadadak.common.storage;

import org.junit.jupiter.api.Test;

import java.net.ServerSocket;
import java.net.Socket;
import java.time.Clock;
import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** 연결은 받고 답하지 않는 저장소. 기본값(5분) 대신 읽기 제한에서 끊겨야 한다. Docker가 필요 없다. */
class ObjectStorageTimeoutTest {

    @Test
    void giveUpOnSilentStorage() throws Exception {
        try (ServerSocket silent = new ServerSocket(0)) {
            Thread.ofVirtual().start(() -> {
                try (Socket ignored = silent.accept()) {
                    Thread.sleep(Duration.ofMinutes(1));
                } catch (Exception ignored) {
                    // 테스트가 끝나며 소켓이 닫힌다
                }
            });
            String endpoint = "http://127.0.0.1:" + silent.getLocalPort();
            ObjectStorage storage = new ObjectStorage(endpoint, endpoint, "wadadak", "wadadak", "secret", Clock.systemUTC());

            long start = System.nanoTime();
            assertThatThrownBy(() -> storage.isUploadedPhoto("review", "review/0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b.jpg"))
                    .isInstanceOf(IllegalStateException.class);
            Duration took = Duration.ofNanos(System.nanoTime() - start);

            assertThat(took).isGreaterThanOrEqualTo(ObjectStorage.IO_TIMEOUT.minusMillis(500)).isLessThan(Duration.ofSeconds(20));
        }
    }
}
