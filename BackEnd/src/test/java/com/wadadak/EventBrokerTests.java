package com.wadadak;

import com.wadadak.event.course.CourseCreatedEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import com.wadadak.event.run.CourseRunStartedEvent;
import com.rabbitmq.client.GetResponse;
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
import org.springframework.modulith.events.EventExternalizationConfiguration;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.rabbitmq.RabbitMQContainer;
import org.testcontainers.utility.DockerImageName;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 이벤트 외부화(EventBrokerConfig, MSA 분리 1단계): run이 받는 이벤트는 run 큐에, run이 보내는 이벤트는 wadadak.run으로,
 * 나머지는 브로커로 보내지 않는다. 실제 이벤트를 발행하므로 모듈 리스너도 돈다(없는 ID라 바뀌는 데이터는 없다).
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

    @BeforeEach
    void emptyRunQueue() {
        rabbitAdmin.purgeQueue(EventBrokerConfig.RUN_QUEUE);
    }

    @Test
    void eventRunConsumesLandsInRunQueueAsJson() {
        MemberWithdrawnEvent event = new MemberWithdrawnEvent(UUID.randomUUID(), Instant.now(), UUID.randomUUID(), Instant.now());

        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));

        Message message = rabbitTemplate.receive(EventBrokerConfig.RUN_QUEUE, RECEIVE_TIMEOUT_MS);
        assertThat(message).isNotNull();
        assertThat(message.getMessageProperties().getReceivedExchange()).isEqualTo("wadadak.member");
        assertThat(message.getMessageProperties().getReceivedRoutingKey()).isEqualTo("MemberWithdrawnEvent");
        assertThat(new String(message.getBody(), StandardCharsets.UTF_8)).contains(event.memberId().toString());
    }

    @Test
    void eventRunPublishesGoesToRunExchangeButNotRunQueue() {
        Queue probe = new AnonymousQueue();
        rabbitAdmin.declareQueue(probe);
        rabbitAdmin.declareBinding(BindingBuilder.bind(probe).to(new TopicExchange("wadadak.run")).with("#"));
        CourseRunStartedEvent event = new CourseRunStartedEvent(UUID.randomUUID(), Instant.now(),
                UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID());

        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));

        Message message = rabbitTemplate.receive(probe.getName(), RECEIVE_TIMEOUT_MS);
        assertThat(message).isNotNull();
        assertThat(message.getMessageProperties().getReceivedRoutingKey()).isEqualTo("CourseRunStartedEvent");
        assertThat(rabbitTemplate.receive(EventBrokerConfig.RUN_QUEUE)).isNull();
    }

    @Test
    void rejectedMessageMovesToDeadLetterQueue() {
        rabbitAdmin.purgeQueue(EventBrokerConfig.RUN_DLQ);
        rabbitTemplate.convertAndSend(EventBrokerConfig.RUN_QUEUE, "poison");

        rabbitTemplate.execute(channel -> {
            GetResponse response = channel.basicGet(EventBrokerConfig.RUN_QUEUE, false);
            channel.basicReject(response.getEnvelope().getDeliveryTag(), false);
            return null;
        });

        assertThat(rabbitTemplate.receive(EventBrokerConfig.RUN_DLQ, RECEIVE_TIMEOUT_MS)).isNotNull();
    }

    @Test
    void selectsOnlyEventsRunSendsOrReceives() {
        Instant now = Instant.now();
        assertThat(externalization.supports(new CourseCreatedEvent(UUID.randomUUID(), now,
                UUID.randomUUID(), UUID.randomUUID(), null))).isFalse();
        assertThat(externalization.supports(new MemberWithdrawnEvent(UUID.randomUUID(), now,
                UUID.randomUUID(), now))).isTrue();
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
