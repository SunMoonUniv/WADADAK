package com.wadadak;

import com.wadadak.event.course.CourseCreatedEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import com.wadadak.event.run.CourseRunStartedEvent;
import com.rabbitmq.client.GetResponse;
import org.awaitility.Awaitility;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.AnonymousQueue;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
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
import org.springframework.context.event.EventListener;
import org.springframework.context.annotation.Import;
import org.springframework.modulith.events.EventExternalizationConfiguration;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.rabbitmq.RabbitMQContainer;
import org.testcontainers.utility.DockerImageName;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 서비스 사이 이벤트(EventBrokerConfig, MSA 분리 4단계): core가 보내는 이벤트는 run 큐에, run이 보낸 이벤트는 core 큐에서 받아
 * core 안에 다시 발행한다. 받은 이벤트는 다시 브로커로 보내지 않는다. 실제 이벤트라 모듈 리스너도 돈다(없는 ID라 바뀌는 데이터는 없다).
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
    RunEventProbe probe;

    @Autowired
    AdminFailedEvents failedEvents;

    @BeforeEach
    void emptyServiceQueues() {
        rabbitAdmin.purgeQueue(EventBrokerConfig.RUN_QUEUE);
        rabbitAdmin.purgeQueue(EventBrokerConfig.QUEUE);
        probe.relayed().clear();
    }

    @Test
    void eventCorePublishesLandsInRunQueueAsJson() {
        MemberWithdrawnEvent event = new MemberWithdrawnEvent(UUID.randomUUID(), Instant.now(), UUID.randomUUID(), Instant.now());

        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));

        Message message = rabbitTemplate.receive(EventBrokerConfig.RUN_QUEUE, RECEIVE_TIMEOUT_MS);
        assertThat(message).isNotNull();
        assertThat(message.getMessageProperties().getReceivedExchange()).isEqualTo("wadadak.member");
        assertThat(message.getMessageProperties().getReceivedRoutingKey()).isEqualTo("MemberWithdrawnEvent");
        assertThat(new String(message.getBody(), StandardCharsets.UTF_8)).contains(event.memberId().toString());
    }

    @Test
    void eventFromRunIsRelayedIntoCore() {
        CourseRunStartedEvent event = new CourseRunStartedEvent(UUID.randomUUID(), Instant.now(),
                UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID());

        // run 서비스가 보내는 모양 그대로(같은 변환기 · exchange · 라우팅 키)
        rabbitTemplate.convertAndSend("wadadak.run", "CourseRunStartedEvent", event);

        Awaitility.await().atMost(Duration.ofSeconds(10)).untilAsserted(() -> assertThat(probe.relayed()).contains(event));
    }

    @Test
    void relayedEventIsNotSentBackToBroker() {
        Queue runExchange = new AnonymousQueue();
        rabbitAdmin.declareQueue(runExchange);
        rabbitAdmin.declareBinding(BindingBuilder.bind(runExchange).to(new TopicExchange("wadadak.run")).with("#"));
        CourseRunStartedEvent event = new CourseRunStartedEvent(UUID.randomUUID(), Instant.now(),
                UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID());

        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));

        assertThat(rabbitTemplate.receive(runExchange.getName(), 2_000)).isNull();
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
    void failedMessageKeepsReasonAndCanBeSentBackOrDeleted() {
        rabbitAdmin.purgeQueue(EventBrokerConfig.RUN_DLQ);
        MemberWithdrawnEvent event = new MemberWithdrawnEvent(UUID.randomUUID(), Instant.now(), UUID.randomUUID(), Instant.now());
        // run이 받은 모양 그대로(wadadak.member exchange · 이벤트 이름 라우팅 키)
        MessageProperties properties = new MessageProperties();
        properties.setReceivedExchange("wadadak.member");
        properties.setReceivedRoutingKey("MemberWithdrawnEvent");
        Message received = new Message(("{\"memberId\":\"" + event.memberId() + "\"}").getBytes(StandardCharsets.UTF_8), properties);

        // 재시도를 다 쓴 뒤 run의 리스너 재시도가 부르는 것과 같다
        new EventBrokerConfig.FailedEventRecoverer(rabbitTemplate, EventBrokerConfig.RUN_DLQ)
                .recover(received, new IllegalStateException("DB가 내려가 있음"));

        Awaitility.await().atMost(Duration.ofSeconds(10)).until(() -> failedEvents.stats().run() == 1);
        List<AdminFailedEvents.Row> rows = failedEvents.list(AdminFailedEvents.Service.RUN);
        assertThat(rows).singleElement().satisfies(row -> {
            assertThat(row.eventType()).isEqualTo("MemberWithdrawnEvent");
            assertThat(row.reason()).contains("DB가 내려가 있음");
            assertThat(row.targetField()).isEqualTo("memberId");
            assertThat(row.targetId()).isEqualTo(event.memberId().toString());
            assertThat(row.failedCount()).isEqualTo(1);
            assertThat(row.failedAt()).isNotNull();
        });
        assertThat(failedEvents.stats().run()).as("목록을 봐도 DLQ에서 빠지지 않는다").isEqualTo(1);

        // 되돌리기: 처음 길(wadadak.member · MemberWithdrawnEvent)로 다시 보내 run 큐에 들어간다
        assertThat(failedEvents.redrive(AdminFailedEvents.Service.RUN).moved()).isEqualTo(1);
        Message back = rabbitTemplate.receive(EventBrokerConfig.RUN_QUEUE, RECEIVE_TIMEOUT_MS);
        assertThat(back).isNotNull();
        assertThat(back.getMessageProperties().getReceivedRoutingKey()).isEqualTo("MemberWithdrawnEvent");
        assertThat(failedEvents.stats().run()).isZero();

        // 지우기
        rabbitTemplate.convertAndSend(EventBrokerConfig.RUN_DLQ, "poison");
        Awaitility.await().atMost(Duration.ofSeconds(10)).until(() -> failedEvents.stats().run() == 1);
        assertThat(failedEvents.purge(AdminFailedEvents.Service.RUN).deleted()).isEqualTo(1);
        assertThat(failedEvents.stats().run()).isZero();
    }

    @Test
    void selectsOnlyEventsCoreSendsToRun() {
        Instant now = Instant.now();
        assertThat(externalization.supports(new CourseCreatedEvent(UUID.randomUUID(), now,
                UUID.randomUUID(), UUID.randomUUID(), null))).isFalse();
        assertThat(externalization.supports(new MemberWithdrawnEvent(UUID.randomUUID(), now,
                UUID.randomUUID(), now))).isTrue();
        assertThat(externalization.supports(new CourseRunStartedEvent(UUID.randomUUID(), now,
                UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID()))).isFalse();
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class BrokerConfig {

        @Bean
        @ServiceConnection
        RabbitMQContainer rabbit() {
            return new RabbitMQContainer(DockerImageName.parse("rabbitmq:4.1-alpine"));
        }

        @Bean
        RunEventProbe runEventProbe() {
            return new RunEventProbe(new CopyOnWriteArrayList<>());
        }
    }

    /** 브로커에서 받아 core 안에 다시 발행된 run 이벤트를 모은다 */
    record RunEventProbe(List<Object> relayed) {

        @EventListener
        void on(CourseRunStartedEvent event) {
            relayed.add(event);
        }
    }
}
