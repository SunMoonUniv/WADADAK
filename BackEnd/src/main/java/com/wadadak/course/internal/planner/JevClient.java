package com.wadadak.course.internal.planner;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.wadadak.common.config.HttpTimeouts;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.time.Duration;
import java.util.Map;
import java.util.Optional;

/**
 * 판단 모델 Jev(TypeSafe 외부 API)에게 문장을 묻는다(개발 정책 1.2). 규칙이 놓친 칸을 보충하는 데만 쓴다({@link SentenceParser}).
 *
 * <p>질문 12개는 {@code planner/jev-questions.json}에 있다. 시험(문장 75개)에서 쓴 영어 문구 그대로라 바꾸면 다시 시험한다.
 * 보내는 것은 문장뿐이다. 위치는 보내지 않는다(정책 B3-A06). 문장 원문은 로그에 남기지 않는다.
 *
 * <p>실패 · 시간 초과 · 키 없음 · 답이 빠진 응답이면 빈 값이다. 그때는 규칙만으로 채운다.
 */
@Slf4j
@Component
class JevClient {

    static final String PATH = "/v1/systemone";

    private final RestClient rest;
    private final String apiKey;
    private final String model;
    private final Map<String, Question> questions;

    @Autowired
    JevClient(@Value("${app.course.planner.jev.base-url}") String baseUrl,
              @Value("${app.course.planner.jev.api-key}") String apiKey,
              @Value("${app.course.planner.jev.model}") String model,
              @Value("${app.course.planner.jev.timeout}") Duration timeout,
              JsonMapper json) {
        this(RestClient.builder().requestFactory(HttpTimeouts.requestFactory(timeout)), baseUrl, apiKey, model, json);
        if (apiKey.isBlank()) {
            log.info("TYPESAFE_API_KEY가 없어 문장 → 폼은 규칙만 쓴다(app.course.planner.jev.api-key)");
        }
    }

    JevClient(RestClient.Builder builder, String baseUrl, String apiKey, String model, JsonMapper json) {
        this.rest = builder.baseUrl(baseUrl).build();
        this.apiKey = apiKey;
        this.model = model;
        try (InputStream in = new ClassPathResource("planner/jev-questions.json").getInputStream()) {
            this.questions = json.readValue(in, new TypeReference<>() {
            });
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    Optional<JevAnswers> ask(String text) {
        if (apiKey.isBlank()) {
            return Optional.empty();
        }
        JevAnswers answers;
        try {
            answers = rest.post().uri(PATH)
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + apiKey)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(new Ask(text, model, questions))
                    .retrieve()
                    .body(JevAnswers.class);
        } catch (RestClientException e) {
            // 오류 메시지 대신 상태 · 원인 종류만 남긴다. 응답 본문에 문장이 되돌아올 수 있다
            log.warn("Jev 호출 실패, 규칙만 쓴다: {}", e instanceof RestClientResponseException r
                    ? r.getStatusCode() : e.getMostSpecificCause().getClass().getSimpleName());
            return Optional.empty();
        }
        if (answers == null || !complete(answers)) {
            log.warn("Jev 응답에 빠진 답이 있어 규칙만 쓴다");
            return Optional.empty();
        }
        return Optional.of(answers);
    }

    /** 질문마다 답이 있다: noul은 값, choice는 보기 중 하나와 그 확률 */
    private boolean complete(JevAnswers answers) {
        if (answers.answers() == null) {
            return false;
        }
        return questions.entrySet().stream().allMatch(q -> {
            Answer a = answers.answers().get(q.getKey());
            if (a == null) {
                return false;
            }
            return "choice".equals(q.getValue().type())
                    ? a.choice() != null && q.getValue().criteria().containsKey(a.choice())
                    && a.probabilities() != null && a.probabilities().get(a.choice()) != null
                    : a.noul() != null;
        });
    }

    private record Ask(String state, String model, Map<String, Question> questions) {
    }

    /** {@code type}: noul(예/아니오 확률) 또는 choice(criteria 중 하나) */
    @JsonInclude(JsonInclude.Include.NON_NULL)
    record Question(String type, String instructions, Map<String, String> criteria) {
    }

    /** Jev 응답. 질문 id별 답({@code answers.{id}}) */
    @JsonIgnoreProperties(ignoreUnknown = true)
    record JevAnswers(Map<String, Answer> answers) {

        /** 예일 확률 0~1. 묻지 않은 질문(밝은 길은 규칙만 읽는다)은 0 */
        double noul(String id) {
            Answer a = answers.get(id);
            return a == null ? 0 : a.noul();
        }

        String choice(String id) {
            return answers.get(id).choice();
        }

        /** 고른 보기의 확률 */
        double confidence(String id) {
            Answer a = answers.get(id);
            return a.probabilities().get(a.choice());
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record Answer(Double noul, String choice, Map<String, Double> probabilities) {
    }
}
