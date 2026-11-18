package com.wadadak;

import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.course.GpsCourseRegisteredEvent;
import com.wadadak.event.member.MemberVisibilityChangedEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import com.wadadak.event.run.CourseActiveRunnersChangedEvent;
import com.wadadak.event.run.CourseRunStartedEvent;
import com.wadadak.event.run.CourseRunTrackEvent;
import com.wadadak.event.run.GpsSourceLinkedEvent;
import com.wadadak.event.run.GpsSourceUnlinkedEvent;
import com.wadadak.event.run.RunRecordDeletedEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import org.springframework.amqp.AmqpRejectAndDontRequeueException;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Declarable;
import org.springframework.amqp.core.Declarables;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.rabbit.retry.MessageRecoverer;
import org.springframework.amqp.rabbit.retry.RepublishMessageRecoverer;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBooleanProperty;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.modulith.events.EventExternalizationConfiguration;
import org.springframework.modulith.events.RoutingTarget;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.json.JsonMapper;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * core 서비스의 이벤트 브로커(MSA 분리 4단계, 개발 정책 5.7·11.3). run 서비스에 같은 모양의 설정이 있다.
 * <ul>
 *   <li>보내기: core가 발행하고 run이 받는 이벤트만 외부화한다. 받은 이벤트까지 고르면 다시 발행하는 순간 브로커로 되돌아가 끝없이 돈다.</li>
 *   <li>받기: core 큐의 메시지를 트랜잭션 안에서 다시 발행한다. 기존 {@code @ApplicationModuleListener}가 그대로 처리하고,
 *       실패하면 core 아웃박스에서 재시도된다. 커밋 전 실패는 브로커 재시도 뒤 DLQ에 남는다(application.yml).</li>
 *   <li>선언: 두 서비스 큐를 양쪽에서 모두 선언한다. 어느 서비스가 먼저 떠도 상대 큐가 있어야 발행한 메시지가 버려지지 않는다.</li>
 * </ul>
 * exchange는 {@code wadadak.{발행 모듈}}, 라우팅 키는 이벤트 이름이다.
 */
@Configuration(proxyBeanMethods = false)
class EventBrokerConfig {

    /** core가 보내고 run이 받는 이벤트. run 큐에 바인딩한다 */
    static final Set<Class<?>> PUBLISHED = Set.of(
            MemberWithdrawnEvent.class, MemberVisibilityChangedEvent.class,
            CourseStatusChangedEvent.class, GpsCourseRegisteredEvent.class);

    /** run이 보내고 core가 받는 이벤트. core 큐에 바인딩한다 */
    static final Set<Class<?>> CONSUMED = Set.of(
            CourseRunStartedEvent.class, RunSessionEndedEvent.class, RunRecordDeletedEvent.class,
            CourseActiveRunnersChangedEvent.class, GpsSourceLinkedEvent.class, GpsSourceUnlinkedEvent.class,
            CourseRunTrackEvent.class);

    static final String QUEUE = "wadadak.core-service";

    /** 재시도를 다 쓴 메시지·역직렬화 실패 메시지가 남는 곳. 기본 exchange로 큐 이름에 보낸다 */
    static final String DLQ = QUEUE + ".dlq";

    static final String RUN_QUEUE = "wadadak.run-service";

    static final String RUN_DLQ = RUN_QUEUE + ".dlq";

    /** DLQ로 옮긴 시각(ISO-8601). 운영자 웹 "실패 이벤트"가 보여 준다 */
    static final String FAILED_AT = "x-failed-at";

    /** 몇 번째로 DLQ에 왔는지. 되돌린 메시지가 또 실패하면 1씩 늘어난다(2 이상이면 코드 문제일 가능성이 크다) */
    static final String FAILED_COUNT = "x-failed-count";

    // ponytail: 기본 외부화 모드는 publisher confirm을 기다리지 않는다(Modulith 2.1 module-listener).
    // 브로커가 꺼져 있으면 전송이 실패해 아웃박스에서 재전송되지만, exchange가 없으면 조용히 버려진다.
    // 그래서 아래 eventBrokerTopology로 exchange를 미리 선언한다. confirm까지 필요하면 outbox 모드(JobRunr 등) 도입.
    @Bean
    EventExternalizationConfiguration eventExternalizationConfiguration() {
        return EventExternalizationConfiguration.externalizing()
                .selectByType(PUBLISHED::contains)
                .routeAllByType(type -> RoutingTarget.forTarget(exchangeOf(type)).andKey(type.getSimpleName()))
                .build();
    }

    /**
     * 브로커 연결이 처음 열릴 때 RabbitAdmin이 선언한다(이미 있으면 그대로).
     * DLQ 인자는 처음부터 붙인다. 큐 인자는 만든 뒤 바꿀 수 없다.
     */
    @Bean
    Declarables eventBrokerTopology() {
        List<Declarable> declarables = new ArrayList<>();
        Stream.concat(PUBLISHED.stream(), CONSUMED.stream())
                .map(EventBrokerConfig::exchangeOf).distinct()
                .forEach(name -> declarables.add(new TopicExchange(name)));
        declareQueue(declarables, QUEUE, DLQ, CONSUMED);
        declareQueue(declarables, RUN_QUEUE, RUN_DLQ, PUBLISHED);
        return new Declarables(declarables);
    }

    /**
     * 재시도(application.yml, 약 6분)를 다 쓴 메시지를 DLQ로 보낼 때 실패 사유를 헤더에 붙인다.
     * <p>
     * [MessageRecoverer] 재시도가 끝난 메시지를 마지막으로 처리하는 부품이다. 이 빈이 있으면 Spring Boot가 리스너 재시도에 끼워 넣는다.
     * 없을 때의 기본값은 메시지를 거절만 해서(큐의 dead-letter 설정으로 DLQ행) 왜 실패했는지가 남지 않는다.
     * <p>
     * [RepublishMessageRecoverer] 메시지를 DLQ로 다시 보내면서 이 헤더를 붙인다:
     * {@code x-exception-message}(오류 메시지) · {@code x-exception-stacktrace} · {@code x-original-exchange} · {@code x-original-routingKey}.
     * 원래 exchange · 라우팅 키가 남아 있어 운영자 웹에서 "되돌리기"를 하면 처음과 같은 길로 다시 보낸다(AdminFailedEvents).
     * 여기에 {@link #FAILED_AT} · {@link #FAILED_COUNT}를 더한다.
     */
    @Bean
    MessageRecoverer failedEventRecoverer(RabbitTemplate rabbitTemplate) {
        return new FailedEventRecoverer(rabbitTemplate, DLQ);
    }

    static class FailedEventRecoverer extends RepublishMessageRecoverer {

        FailedEventRecoverer(RabbitTemplate rabbitTemplate, String dlq) {
            // 기본 exchange("")에 DLQ 이름을 라우팅 키로 주면 그 큐로 바로 들어간다
            super(rabbitTemplate, "", dlq);
        }

        @Override
        protected Map<? extends String, ?> additionalHeaders(Message message, Throwable cause) {
            Object previous = message.getMessageProperties().getHeader(FAILED_COUNT);
            long count = previous instanceof Number n ? n.longValue() + 1 : 1;
            return Map.of(FAILED_AT, Instant.now().toString(), FAILED_COUNT, count);
        }
    }

    /** 브로커를 쓰는 환경(공용 서버)에서만 받는다. 로컬 · 테스트는 브로커 없이 뜬다 */
    @Bean
    @ConditionalOnBooleanProperty("spring.modulith.events.externalization.enabled")
    BrokerEventRelay brokerEventRelay(JsonMapper json, TransactionTemplate transaction, ApplicationEventPublisher events) {
        return new BrokerEventRelay(json, transaction, events);
    }

    static class BrokerEventRelay {

        private static final Map<String, Class<?>> TYPES = CONSUMED.stream()
                .collect(Collectors.toUnmodifiableMap(Class::getSimpleName, Function.identity()));

        private final JsonMapper json;
        private final TransactionTemplate transaction;
        private final ApplicationEventPublisher events;

        BrokerEventRelay(JsonMapper json, TransactionTemplate transaction, ApplicationEventPublisher events) {
            this.json = json;
            this.transaction = transaction;
            this.events = events;
        }

        @RabbitListener(queues = QUEUE)
        void relay(Message message) {
            String key = message.getMessageProperties().getReceivedRoutingKey();
            Class<?> type = TYPES.get(key);
            if (type == null) {
                throw new AmqpRejectAndDontRequeueException("core가 받지 않는 이벤트: " + key);
            }
            Object event = json.readValue(message.getBody(), type);
            transaction.executeWithoutResult(status -> events.publishEvent(event));
        }
    }

    private static void declareQueue(List<Declarable> declarables, String name, String dlq, Set<Class<?>> types) {
        Queue queue = QueueBuilder.durable(name).deadLetterExchange("").deadLetterRoutingKey(dlq).build();
        declarables.add(queue);
        declarables.add(QueueBuilder.durable(dlq).build());
        types.forEach(type -> declarables.add(BindingBuilder.bind(queue)
                .to(new TopicExchange(exchangeOf(type))).with(type.getSimpleName())));
    }

    /** {@code com.wadadak.event.run.X} → {@code wadadak.run}. 이벤트 패키지 이름이 발행 모듈이다(개발 정책 5.3) */
    static String exchangeOf(Class<?> type) {
        String pkg = type.getPackageName();
        return "wadadak." + pkg.substring(pkg.lastIndexOf('.') + 1);
    }
}
