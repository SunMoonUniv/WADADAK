package com.wadadak;

import com.rabbitmq.client.GetResponse;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import lombok.RequiredArgsConstructor;
import org.springframework.amqp.AmqpException;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.ChannelCallback;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.rabbit.retry.RepublishMessageRecoverer;
import org.springframework.amqp.rabbit.support.DefaultMessagePropertiesConverter;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Map;

/**
 * 운영자 웹 "실패 이벤트"(DLQ). DLQ에 남은 메시지를 보고, 원래 큐로 되돌리거나 지운다.
 * <p>
 * DLQ는 core · run 서비스 큐마다 하나씩 있다(EventBrokerConfig). 둘 다 같은 브로커에 있어 core가 둘 다 다룬다.
 * 브로커에 연결하지 못하면(로컬에서 브로커를 안 띄운 경우 등) COMMON-006에 그 사유를 담아 돌려준다.
 * <p>
 * [채널] 브로커와 주고받는 통로다. {@link RabbitTemplate#execute}가 빌려준 채널로 큐를 직접 다룬다.
 * RabbitMQ 큐에는 "읽기만 하기"가 없어서, 메시지를 꺼낸 뒤(basicGet) 확인하지 않은 채로 두었다가 다시 넣는다(basicNack + requeue).
 * 도중에 서버가 죽어도 확인하지 않은 메시지는 브로커가 큐에 되돌리므로 사라지지 않는다.
 */
@Component
@RequiredArgsConstructor
class AdminFailedEvents {

    /** 목록에 보여 줄 최대 개수. 이보다 많이 쌓였다면 하나씩 볼 상황이 아니라 큰 장애다 */
    static final int LIST_LIMIT = 50;

    /** 원문 · 스택이 길면(경로 이벤트 등) 화면이 무거워져 앞부분만 보낸다 */
    private static final int TEXT_LIMIT = 4_000;

    /** 메시지 원문에서 "대상"으로 보여 줄 ID. 앞에 있는 것을 먼저 쓴다 */
    private static final List<String> TARGET_FIELDS = List.of("runRecordId", "runSessionId", "courseId", "memberId");

    private final RabbitTemplate rabbitTemplate;
    private final JsonMapper jsonMapper;
    private final DefaultMessagePropertiesConverter converter = new DefaultMessagePropertiesConverter();

    /** 어느 서비스가 처리하지 못한 메시지인지. 서비스마다 DLQ가 하나다 */
    enum Service {
        CORE(EventBrokerConfig.DLQ),
        RUN(EventBrokerConfig.RUN_DLQ);

        final String dlq;

        Service(String dlq) {
            this.dlq = dlq;
        }
    }

    record Stats(long core, long run) {
    }

    /**
     * @param eventType     이벤트 이름(원래 라우팅 키). 원래 길을 모르면 null
     * @param targetField   대상 ID가 어느 칸인지(runRecordId · courseId 등). 없으면 null
     * @param failedAt      DLQ로 옮긴 시각. 실패 사유 헤더를 붙이기 전(2026-11-18 전) 메시지는 dead-letter 시각
     * @param failedCount   몇 번째로 DLQ에 왔는지
     * @param reason        오류 메시지. 역직렬화 실패처럼 재시도 없이 바로 거절된 메시지는 null
     */
    record Row(String eventType, String targetField, String targetId, Instant occurredAt, Instant failedAt,
               long failedCount, String reason, String stackTrace, String originalExchange, String payload,
               boolean payloadTruncated) {
    }

    record Moved(int moved, int skipped) {
    }

    record Deleted(int deleted) {
    }

    Stats stats() {
        return withChannel(channel -> new Stats(channel.messageCount(Service.CORE.dlq), channel.messageCount(Service.RUN.dlq)));
    }

    /** 앞에서부터 최대 {@link #LIST_LIMIT}개. 다 본 뒤 그대로 큐에 되돌린다 */
    List<Row> list(Service service) {
        return withChannel(channel -> {
            List<Row> rows = new ArrayList<>();
            long lastTag = -1;
            try {
                for (int i = 0; i < LIST_LIMIT; i++) {
                    GetResponse response = channel.basicGet(service.dlq, false); // false: 꺼내도 아직 확인(ack)하지 않는다
                    if (response == null) {
                        break;
                    }
                    lastTag = response.getEnvelope().getDeliveryTag();
                    rows.add(row(response));
                }
            } finally {
                if (lastTag >= 0) {
                    // multiple=true: 이 번호까지 꺼낸 것을 모두, requeue=true: 큐에 다시 넣는다
                    channel.basicNack(lastTag, true, true);
                }
            }
            return rows;
        });
    }

    /**
     * 지금 DLQ에 있는 메시지를 처음 왔던 길(원래 exchange · 라우팅 키)로 다시 보낸다. 받는 서비스가 다시 처리한다.
     * 원래 길을 알 수 없는 메시지는 DLQ에 그대로 둔다(skipped).
     * <p>
     * 큐 이름으로 바로 넣지 않는 이유: 받는 쪽(BrokerEventRelay)이 라우팅 키로 이벤트 종류를 알아낸다. 큐 이름으로 넣으면 모르는 이벤트가 된다.
     * 다시 처리하다 또 실패하면 재시도(약 6분) 뒤 DLQ로 돌아온다. 리스너가 멱등이라 이미 처리된 이벤트를 되돌려도 두 번 반영되지 않는다.
     */
    Moved redrive(Service service) {
        return withChannel(channel -> {
            long total = channel.messageCount(service.dlq); // 지금 있는 만큼만. 도중에 새로 들어온 것은 다음에
            int moved = 0;
            List<Long> skipped = new ArrayList<>();
            try {
                for (long i = 0; i < total; i++) {
                    GetResponse response = channel.basicGet(service.dlq, false);
                    if (response == null) {
                        break;
                    }
                    long tag = response.getEnvelope().getDeliveryTag();
                    Route route = originalRoute(properties(response));
                    if (route == null) {
                        skipped.add(tag); // 확인하지 않고 들고 있다가 끝에 되돌린다. 바로 되돌리면 다음 basicGet이 또 꺼낸다
                        continue;
                    }
                    // ponytail: 발행 확인(publisher confirm) 없이 보낸다. exchange · 바인딩은 EventBrokerConfig가 미리 선언해 두어
                    // 실제로 버려질 일은 없다. 잃으면 안 되는 상황이 생기면 confirm 채널로 바꾼다
                    channel.basicPublish(route.exchange(), route.routingKey(), response.getProps(), response.getBody());
                    channel.basicAck(tag, false); // 보낸 뒤에 DLQ에서 지운다. 그 사이에 죽으면 중복이 생기지만 리스너가 멱등이다
                    moved++;
                }
            } finally {
                for (long tag : skipped) {
                    channel.basicNack(tag, false, true);
                }
            }
            return new Moved(moved, skipped.size());
        });
    }

    /** DLQ를 비운다. 되돌릴 수 없다 */
    Deleted purge(Service service) {
        return withChannel(channel -> new Deleted(channel.queuePurge(service.dlq).getMessageCount()));
    }

    private Row row(GetResponse response) {
        MessageProperties properties = properties(response);
        Route route = originalRoute(properties);
        Map<String, Object> death = firstDeath(properties);
        Object failedAt = properties.getHeader(EventBrokerConfig.FAILED_AT);
        Object failedCount = properties.getHeader(EventBrokerConfig.FAILED_COUNT);

        String body = new String(response.getBody(), StandardCharsets.UTF_8);
        JsonNode json = readJson(body);
        String targetField = json == null ? null : TARGET_FIELDS.stream().filter(json::hasNonNull).findFirst().orElse(null);
        // GpsSourceUnlinkedEvent는 끊긴 연결 이벤트를 source 안에 담는다
        if (targetField == null && json != null && json.path("source").hasNonNull("runRecordId")) {
            targetField = "runRecordId";
            json = json.get("source");
        }

        return new Row(
                route == null ? null : route.routingKey(),
                targetField,
                targetField == null ? null : json.get(targetField).asString(),
                json == null || !json.hasNonNull("occurredAt") ? null : parseInstant(json.get("occurredAt").asString()),
                failedAt != null ? parseInstant(failedAt.toString()) : deathTime(death),
                failedCount instanceof Number n ? n.longValue() : deathCount(death),
                header(properties, RepublishMessageRecoverer.X_EXCEPTION_MESSAGE),
                clip(header(properties, RepublishMessageRecoverer.X_EXCEPTION_STACKTRACE)),
                route == null ? null : route.exchange(),
                clip(body),
                body.length() > TEXT_LIMIT);
    }

    private record Route(String exchange, String routingKey) {
    }

    /**
     * 처음 왔던 길. 실패 사유 헤더(RepublishMessageRecoverer)가 있으면 그것, 없으면 브로커가 dead-letter 때 남긴 x-death에서 찾는다.
     * 역직렬화 실패처럼 재시도 없이 거절된 메시지는 x-death만 있다.
     */
    private Route originalRoute(MessageProperties properties) {
        String exchange = header(properties, RepublishMessageRecoverer.X_ORIGINAL_EXCHANGE);
        String routingKey = header(properties, RepublishMessageRecoverer.X_ORIGINAL_ROUTING_KEY);
        if (exchange != null && routingKey != null) {
            return new Route(exchange, routingKey);
        }
        Map<String, Object> death = firstDeath(properties);
        if (death != null && death.get("exchange") != null && death.get("routing-keys") instanceof List<?> keys && !keys.isEmpty()) {
            return new Route(death.get("exchange").toString(), keys.getFirst().toString());
        }
        return null;
    }

    /** 브로커가 dead-letter할 때마다 붙이는 기록 중 가장 최근 것 */
    private static Map<String, Object> firstDeath(MessageProperties properties) {
        List<Map<String, ?>> deaths = properties.getXDeathHeader();
        if (deaths == null || deaths.isEmpty()) {
            return null;
        }
        @SuppressWarnings("unchecked")
        Map<String, Object> first = (Map<String, Object>) deaths.getFirst();
        return first;
    }

    private static Instant deathTime(Map<String, Object> death) {
        return death != null && death.get("time") instanceof Date time ? time.toInstant() : null;
    }

    private static long deathCount(Map<String, Object> death) {
        return death != null && death.get("count") instanceof Number count ? count.longValue() : 1;
    }

    /** 브로커가 준 원시 속성을 Spring 모양으로 바꾼다. 헤더의 문자열(LongString)도 String이 된다 */
    private MessageProperties properties(GetResponse response) {
        return converter.toMessageProperties(response.getProps(), response.getEnvelope(), "UTF-8");
    }

    private static String header(MessageProperties properties, String name) {
        Object value = properties.getHeader(name);
        return value == null ? null : value.toString();
    }

    private JsonNode readJson(String body) {
        try {
            JsonNode node = jsonMapper.readTree(body);
            return node.isObject() ? node : null;
        } catch (RuntimeException e) {
            return null; // 이벤트가 아닌 메시지(역직렬화 실패의 원인)일 수 있다
        }
    }

    private static Instant parseInstant(String text) {
        try {
            return Instant.parse(text);
        } catch (RuntimeException e) {
            return null;
        }
    }

    private static String clip(String text) {
        return text == null || text.length() <= TEXT_LIMIT ? text : text.substring(0, TEXT_LIMIT);
    }

    private <T> T withChannel(ChannelCallback<T> callback) {
        try {
            return rabbitTemplate.execute(callback);
        } catch (AmqpException e) {
            throw new AppException(CommonErrorCode.INTERNAL_ERROR, "메시지 브로커(RabbitMQ)에 연결하지 못했거나 큐를 다루지 못했습니다.");
        }
    }
}
