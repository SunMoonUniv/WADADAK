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
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Declarable;
import org.springframework.amqp.core.Declarables;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.modulith.events.EventExternalizationConfiguration;
import org.springframework.modulith.events.RoutingTarget;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;

/**
 * 이벤트 외부화(MSA 분리 1단계, 개발 정책 5.7·11.3). run이 보내고 받는 이벤트를 RabbitMQ에도 발행한다.
 * 모놀리스 안의 전달은 그대로다. 켜고 끄는 값은 {@code spring.modulith.events.externalization.enabled}.
 * <ul>
 *   <li>exchange는 {@code wadadak.{발행 모듈}}, 라우팅 키는 이벤트 이름이다. 큐는 필요한 이벤트 이름만 바인딩한다.</li>
 *   <li>브로커에서 받는 리스너는 두지 않는다. 지금 받으면 자기가 보낸 이벤트를 다시 발행해 끝없이 돈다.
 *       받는 쪽은 분리 전환(11.3 4단계) 때 서비스마다 둔다.</li>
 *   <li>run 큐는 지금 선언한다. 전환 전후에 나간 이벤트가 큐에 남아 run 서비스가 처음 뜰 때 받는다.
 *       그때까지 큐가 커진다(이미 처리한 이벤트는 run의 멱등 기록이 걸러낸다, 개발 정책 5.4).
 *       run 서비스가 쓸 아웃박스·ShedLock 테이블도 같은 배포에서 만든다({@code db/migration/run}).</li>
 * </ul>
 * 분리 뒤에는 서비스마다 자기 모듈이 발행한 이벤트만 고른다. 그래서 공통 모듈이 아니라 애플리케이션 루트에 둔다.
 */
@Configuration(proxyBeanMethods = false)
class EventBrokerConfig {

    /** run이 보내는 이벤트(run → core) */
    static final Set<Class<?>> RUN_PUBLISHED = Set.of(
            CourseRunStartedEvent.class, RunSessionEndedEvent.class, RunRecordDeletedEvent.class,
            CourseActiveRunnersChangedEvent.class, GpsSourceLinkedEvent.class, GpsSourceUnlinkedEvent.class,
            CourseRunTrackEvent.class);

    /** run이 받는 이벤트(core → run). run 큐에 바인딩한다 */
    static final Set<Class<?>> RUN_CONSUMED = Set.of(
            MemberWithdrawnEvent.class, MemberVisibilityChangedEvent.class,
            CourseStatusChangedEvent.class, GpsCourseRegisteredEvent.class);

    static final String RUN_QUEUE = "wadadak.run-service";

    /** 재시도를 다 쓴 메시지·역직렬화 실패 메시지가 남는 곳(개발 정책 5.7). 기본 exchange로 큐 이름에 보낸다 */
    static final String RUN_DLQ = RUN_QUEUE + ".dlq";

    // ponytail: 기본 외부화 모드는 publisher confirm을 기다리지 않는다(Modulith 2.1 module-listener).
    // 브로커가 꺼져 있으면 전송이 실패해 아웃박스에서 재전송되지만, exchange가 없으면 조용히 버려진다.
    // 그래서 아래 eventBrokerTopology로 exchange를 미리 선언한다. confirm까지 필요하면 outbox 모드(JobRunr 등) 도입.
    @Bean
    EventExternalizationConfiguration eventExternalizationConfiguration() {
        return EventExternalizationConfiguration.externalizing()
                .selectByType(type -> RUN_PUBLISHED.contains(type) || RUN_CONSUMED.contains(type))
                .routeAllByType(type -> RoutingTarget.forTarget(exchangeOf(type)).andKey(type.getSimpleName()))
                .build();
    }

    /**
     * 브로커 연결이 처음 열릴 때 RabbitAdmin이 선언한다(이미 있으면 그대로).
     * DLQ 인자는 지금 붙인다. 큐 인자는 만든 뒤 바꿀 수 없어, 나중에 붙이려면 쌓인 큐를 지우고 다시 만들어야 한다.
     */
    @Bean
    Declarables eventBrokerTopology() {
        List<Declarable> declarables = new ArrayList<>();
        Stream.concat(RUN_PUBLISHED.stream(), RUN_CONSUMED.stream())
                .map(EventBrokerConfig::exchangeOf).distinct()
                .forEach(name -> declarables.add(new TopicExchange(name)));
        Queue runQueue = QueueBuilder.durable(RUN_QUEUE)
                .deadLetterExchange("").deadLetterRoutingKey(RUN_DLQ).build();
        declarables.add(runQueue);
        declarables.add(QueueBuilder.durable(RUN_DLQ).build());
        RUN_CONSUMED.forEach(type -> declarables.add(BindingBuilder.bind(runQueue)
                .to(new TopicExchange(exchangeOf(type))).with(type.getSimpleName())));
        return new Declarables(declarables);
    }

    /** {@code com.wadadak.event.run.X} → {@code wadadak.run}. 이벤트 패키지 이름이 발행 모듈이다(개발 정책 5.3) */
    static String exchangeOf(Class<?> type) {
        String pkg = type.getPackageName();
        return "wadadak." + pkg.substring(pkg.lastIndexOf('.') + 1);
    }
}
