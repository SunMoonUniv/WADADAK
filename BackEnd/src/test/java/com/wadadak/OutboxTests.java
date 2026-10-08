package com.wadadak;

import com.wadadak.event.IntegrationEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.modulith.events.core.EventSerializer;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

/**
 * 아웃박스(개발 정책 5.1~5.5): 커밋 후 비동기 전달, 완료 기록 삭제, 모르는 필드 무시.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import({TestcontainersConfiguration.class, OutboxTests.ListenerConfig.class})
class OutboxTests {

    @Autowired
    TransactionTemplate transactionTemplate;

    @Autowired
    ApplicationEventPublisher publisher;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    EventSerializer eventSerializer;

    @Autowired
    Recorder recorder;

    @Test
    void deliversAfterCommitOnAnotherThreadAndDeletesCompletedPublication() {
        PingEvent event = new PingEvent(UUID.randomUUID(), Instant.now());

        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));

        await().atMost(Duration.ofSeconds(10)).untilAsserted(() -> {
            assertThat(recorder.deliveryOf(event.eventId())).isNotNull();
            assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM common.event_publication", Long.class)).isZero();
        });
        Delivery delivery = recorder.deliveryOf(event.eventId());
        assertThat(delivery.storedPublications()).isEqualTo(1);
        assertThat(delivery.thread()).isNotEqualTo(Thread.currentThread().getName());
    }

    @Test
    void ignoresFieldsAddedLaterWhenReadingStoredEvent() {
        Instant now = Instant.now().truncatedTo(ChronoUnit.MILLIS);
        MemberWithdrawnEvent event = new MemberWithdrawnEvent(UUID.randomUUID(), now, UUID.randomUUID(), now);
        String stored = eventSerializer.serialize(event).toString();

        String withNewField = stored.replaceFirst("\\{", "{\"addedLater\":1,");

        assertThat(eventSerializer.deserialize(withNewField, MemberWithdrawnEvent.class)).isEqualTo(event);
    }

    /**
     * 테스트 전용 이벤트. 실제 이벤트(예: MemberWithdrawnEvent)를 발행하면
     * 다른 모듈이 그 이벤트의 리스너를 추가하는 순간 이 테스트에서도 실행된다.
     */
    public record PingEvent(UUID eventId, Instant occurredAt) implements IntegrationEvent {
    }

    /** 받은 시점에 아웃박스에 남아 있던 기록 수와 실행 스레드. */
    record Delivery(long storedPublications, String thread) {
    }

    /** 리스너 빈은 AOP 프록시라 필드 대신 메서드로 읽는다. */
    static class Recorder {

        private final JdbcTemplate jdbcTemplate;
        private final Map<UUID, Delivery> deliveries = new ConcurrentHashMap<>();

        Recorder(JdbcTemplate jdbcTemplate) {
            this.jdbcTemplate = jdbcTemplate;
        }

        @ApplicationModuleListener
        public void on(PingEvent event) {
            Long stored = jdbcTemplate.queryForObject("SELECT count(*) FROM common.event_publication", Long.class);
            deliveries.put(event.eventId(), new Delivery(stored, Thread.currentThread().getName()));
        }

        public Delivery deliveryOf(UUID eventId) {
            return deliveries.get(eventId);
        }
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class ListenerConfig {

        @Bean
        Recorder recorder(JdbcTemplate jdbcTemplate) {
            return new Recorder(jdbcTemplate);
        }
    }
}
