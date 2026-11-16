package com.wadadak;

import com.wadadak.event.member.MemberWithdrawnEvent;
import com.wadadak.event.run.CourseRunStartedEvent;
import org.awaitility.Awaitility;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.AnonymousQueue;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.core.RabbitAdmin;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.events.EventExternalizationConfiguration;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.rabbitmq.RabbitMQContainer;
import org.testcontainers.utility.DockerImageName;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * run 서비스의 서비스 사이 이벤트(EventBrokerConfig, MSA 분리 4단계): run이 보내는 이벤트는 core 큐에,
 * core가 보낸 이벤트는 run 큐에서 받아 run 리스너까지 간다. 받은 이벤트는 다시 브로커로 보내지 않는다.
 */
@SpringBootTest(properties = "spring.modulith.events.externalization.enabled=true")
@ActiveProfiles("test")
@Import({TestcontainersConfiguration.class, EventBrokerTests.BrokerConfig.class})
class EventBrokerTests {

    private static final long RECEIVE_TIMEOUT_MS = 10_000;

    @Autowired
    TransactionTemplate transactionTemplate;

    @Autowired
    ApplicationEventPublisher publisher;

    @Autowired
    RabbitTemplate rabbitTemplate;

    @Autowired
    RabbitAdmin rabbitAdmin;

    @Autowired
    EventExternalizationConfiguration externalization;

    @Autowired
    JdbcTemplate jdbc;

    @BeforeEach
    void emptyCoreQueue() {
        rabbitAdmin.purgeQueue(EventBrokerConfig.CORE_QUEUE);
    }

    @Test
    void eventRunPublishesLandsInCoreQueue() {
        CourseRunStartedEvent event = new CourseRunStartedEvent(UUID.randomUUID(), Instant.now(),
                UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID());

        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));

        Message message = rabbitTemplate.receive(EventBrokerConfig.CORE_QUEUE, RECEIVE_TIMEOUT_MS);
        assertThat(message).isNotNull();
        assertThat(message.getMessageProperties().getReceivedExchange()).isEqualTo("wadadak.run");
        assertThat(message.getMessageProperties().getReceivedRoutingKey()).isEqualTo("CourseRunStartedEvent");
    }

    @Test
    void withdrawalFromCoreReachesRunListener() {
        UUID member = UUID.randomUUID();
        MemberWithdrawnEvent event = new MemberWithdrawnEvent(UUID.randomUUID(), Instant.now(), member, Instant.now());

        // core 서비스가 보내는 모양 그대로(같은 변환기 · exchange · 라우팅 키)
        rabbitTemplate.convertAndSend("wadadak.member", "MemberWithdrawnEvent", event);

        Awaitility.await().atMost(Duration.ofSeconds(15)).untilAsserted(() -> assertThat(
                jdbc.queryForObject("SELECT count(*) FROM run.withdrawn_members WHERE member_id = ?", Integer.class, member))
                .isOne());
    }

    @Test
    void relayedEventIsNotSentBackToBroker() {
        Queue memberExchange = new AnonymousQueue();
        rabbitAdmin.declareQueue(memberExchange);
        rabbitAdmin.declareBinding(BindingBuilder.bind(memberExchange).to(new TopicExchange("wadadak.member")).with("#"));
        MemberWithdrawnEvent event = new MemberWithdrawnEvent(UUID.randomUUID(), Instant.now(), UUID.randomUUID(), Instant.now());

        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));

        assertThat(rabbitTemplate.receive(memberExchange.getName(), 2_000)).isNull();
    }

    @Test
    void selectsOnlyEventsRunSendsToCore() {
        Instant now = Instant.now();
        assertThat(externalization.supports(new CourseRunStartedEvent(UUID.randomUUID(), now,
                UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID()))).isTrue();
        assertThat(externalization.supports(new MemberWithdrawnEvent(UUID.randomUUID(), now,
                UUID.randomUUID(), now))).isFalse();
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class BrokerConfig {

        @Bean
        @ServiceConnection
        RabbitMQContainer rabbit() {
            return new RabbitMQContainer(DockerImageName.parse("rabbitmq:4.1-alpine"));
        }
    }
}
