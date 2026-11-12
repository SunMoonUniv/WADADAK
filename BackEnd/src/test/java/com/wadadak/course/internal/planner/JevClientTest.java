package com.wadadak.course.internal.planner;

import com.wadadak.course.internal.planner.JevClient.JevAnswers;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.client.ResponseActions;
import org.springframework.web.client.RestClient;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.net.http.HttpTimeoutException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/** Jev 요청 모양과 실패 처리. 실제 TypeSafe 대신 가짜 서버({@link MockRestServiceServer})가 답한다. 응답은 시험 때 받은 것 */
class JevClientTest {

    private static final String URL = "https://api.typesafe.ai/v1/systemone";
    private static final String TEXT = "선문대 정문에서 출발해서 5km 정도 한 바퀴 도는 평지 코스 만들어줘";
    private static final JsonMapper JSON = JsonMapper.builder().build();

    private MockRestServiceServer jev;
    private JevClient client;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder();
        jev = MockRestServiceServer.bindTo(builder).build();
        client = new JevClient(builder, "https://api.typesafe.ai", "test-key", "jev-latest", JSON);
    }

    @Test
    void sendsOnlyTheSentenceAndReadsTheAnswers() {
        jev.expect(requestTo(URL))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer test-key"))
                .andExpect(jsonPath("$.*", hasSize(3)))
                .andExpect(jsonPath("$.state").value(TEXT))
                .andExpect(jsonPath("$.model").value("jev-latest"))
                .andExpect(jsonPath("$.questions.*", hasSize(12)))
                .andExpect(jsonPath("$.questions.shape.criteria.via_landmark").exists())
                .andExpect(jsonPath("$.questions.pref_flat.criteria").doesNotExist())
                .andRespond(withSuccess(recordedResponse(), MediaType.APPLICATION_JSON));

        Optional<JevAnswers> answers = client.ask(TEXT);

        jev.verify();
        assertThat(answers).hasValueSatisfying(a -> {
            assertThat(a.noul("pref_flat")).isEqualTo(0.9);
            assertThat(a.choice("start")).isEqualTo("named_place");
            assertThat(a.confidence("shape")).isEqualTo(1.0);
        });
    }

    /** SentenceParser는 Pref마다 {@code pref_} + 소문자 이름의 답을 읽는다. 질문이 빠지면 parse가 NullPointerException으로 죽는다 */
    @Test
    void asksAQuestionForEveryPref() {
        ResponseActions request = jev.expect(requestTo(URL));
        for (Pref pref : Pref.values()) {
            request.andExpect(jsonPath("$.questions.pref_" + pref.name().toLowerCase(Locale.ROOT)).exists());
        }
        request.andRespond(withSuccess(recordedResponse(), MediaType.APPLICATION_JSON));

        client.ask(TEXT);

        jev.verify();
    }

    @Test
    void serverErrorMeansRulesOnly() {
        jev.expect(requestTo(URL)).andRespond(withServerError());

        assertThat(client.ask(TEXT)).isEmpty();
    }

    /** 2초(app.course.planner.jev.timeout)가 지나면 JdkClientHttpRequestFactory가 HttpTimeoutException을 던진다 */
    @Test
    void timeoutMeansRulesOnly() {
        jev.expect(requestTo(URL)).andRespond(request -> {
            throw new HttpTimeoutException("request timed out");
        });

        assertThat(client.ask(TEXT)).isEmpty();
    }

    @Test
    void missingAnswersMeanRulesOnly() {
        jev.expect(requestTo(URL)).andRespond(withSuccess("{\"answers\": {\"on_topic\": {\"type\": \"noul\", \"noul\": 0.9}}}",
                MediaType.APPLICATION_JSON));

        assertThat(client.ask(TEXT)).isEmpty();
    }

    @Test
    void noKeyMeansNoCall() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer noCalls = MockRestServiceServer.bindTo(builder).build();
        JevClient noKey = new JevClient(builder, "https://api.typesafe.ai", "", "jev-latest", JSON);

        assertThat(noKey.ask(TEXT)).isEmpty();
        noCalls.verify(); // 요청이 가면 "No further requests expected"로 실패한다
    }

    /** 시험 때 첫 문장에 받은 답을 실제 응답 모양({model, answers, usage})으로 */
    private static String recordedResponse() {
        List<Map<String, Object>> recorded = SentenceRulesTest.read("planner/jev-answers.json", new TypeReference<>() {
        });
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("model", "jev-1.14.0");
        response.put("answers", recorded.getFirst().get("answers"));
        response.put("usage", Map.of("input_tokens", 950, "output_tokens", 60));
        return JSON.writeValueAsString(response);
    }
}
