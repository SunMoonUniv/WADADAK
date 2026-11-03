package com.wadadak.notification.internal;

import com.wadadak.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 기기 토큰 · 알림 설정 API(F14 · F4). 회원 · 토큰은 매번 새 값이라 다른 시험과 섞이지 않는다 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class NotificationApiTest {

    private static final String TOKENS = "/api/v1/notifications/tokens";
    private static final String SETTINGS = "/api/v1/notifications/settings";

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void registeringTheSameTokenAgainKeepsOneDevice() {
        UUID me = UUID.randomUUID();
        String token = "token-" + me;

        assertThat(register(me, token, "ANDROID")).hasStatusOk();
        assertThat(register(me, token, "ANDROID")).hasStatusOk();

        assertThat(tokensOf(me)).containsExactly(token);
    }

    @Test
    void aDeviceMovesToTheAccountThatLoggedInLast() {
        UUID before = UUID.randomUUID();
        UUID after = UUID.randomUUID();
        String token = "shared-" + before;

        register(before, token, "ANDROID");
        register(after, token, "ANDROID");

        assertThat(tokensOf(before)).isEmpty();
        assertThat(tokensOf(after)).containsExactly(token);
    }

    @Test
    void keepsTheTenMostRecentDevices() {
        UUID me = UUID.randomUUID();
        for (int i = 0; i < 12; i++) {
            register(me, "device-" + i + "-" + me, "ANDROID");
        }

        assertThat(tokensOf(me)).hasSize(10).doesNotContain("device-0-" + me, "device-1-" + me);
    }

    @Test
    void removesOnlyMyOwnToken() {
        UUID me = UUID.randomUUID();
        UUID other = UUID.randomUUID();
        register(me, "mine-" + me, "ANDROID");
        register(other, "theirs-" + other, "IOS");

        assertThat(remove(me, "theirs-" + other)).as("남의 토큰은 그냥 넘어간다").hasStatusOk();
        assertThat(remove(me, "mine-" + me)).hasStatusOk();
        assertThat(remove(me, "mine-" + me)).as("다시 지워도 오류가 아니다").hasStatusOk();

        assertThat(tokensOf(me)).isEmpty();
        assertThat(tokensOf(other)).containsExactly("theirs-" + other);
    }

    @Test
    void rejectsAMalformedToken() {
        UUID me = UUID.randomUUID();

        for (String body : List.of("{\"token\": \"\", \"platform\": \"ANDROID\"}",
                "{\"token\": \"t\", \"platform\": \"WINDOWS\"}",
                "{\"token\": \"t\"}",
                "{\"token\": \"" + "x".repeat(1025) + "\", \"platform\": \"ANDROID\"}")) {
            assertThat(mvc.put().uri(TOKENS).with(member(me)).contentType(MediaType.APPLICATION_JSON).content(body).exchange())
                    .as(body.length() > 80 ? "1025자" : body)
                    .hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
        }
        assertThat(tokensOf(me)).isEmpty();
    }

    @Test
    void settingsStartOnAndCanBeTurnedOff() {
        UUID me = UUID.randomUUID();

        assertThat(mvc.get().uri(SETTINGS).with(member(me)).exchange())
                .hasStatusOk().bodyJson().extractingPath("$.data.courseExpiringSoon").isEqualTo(true);

        assertThat(changeSettings(me, "{\"courseExpiringSoon\": false}"))
                .hasStatusOk().bodyJson().extractingPath("$.data.courseExpiringSoon").isEqualTo(false);
        assertThat(mvc.get().uri(SETTINGS).with(member(me)).exchange())
                .bodyJson().extractingPath("$.data.courseExpiringSoon").isEqualTo(false);

        assertThat(changeSettings(me, "{}")).as("값을 빠뜨리면 끄기로 보지 않는다")
                .hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    @Test
    void aWithdrawnMemberWithAStillValidTokenIsAskedToLogInAgain() {
        UUID me = UUID.randomUUID();
        jdbc.update("INSERT INTO notification.withdrawn_members VALUES (?, now(), now(), now())", me);

        assertThat(register(me, "late-" + me, "ANDROID"))
                .hasStatus(HttpStatus.UNAUTHORIZED).bodyJson().extractingPath("$.code").isEqualTo("COMMON-002");
        assertThat(mvc.get().uri(SETTINGS).with(member(me)).exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(changeSettings(me, "{\"courseExpiringSoon\": false}")).hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(tokensOf(me)).isEmpty();
    }

    @Test
    void needsLogin() {
        assertThat(mvc.get().uri(SETTINGS).exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(mvc.put().uri(TOKENS).contentType(MediaType.APPLICATION_JSON)
                .content("{\"token\": \"t\", \"platform\": \"ANDROID\"}").exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private MvcTestResult register(UUID member, String token, String platform) {
        return mvc.put().uri(TOKENS).with(member(member)).contentType(MediaType.APPLICATION_JSON)
                .content("{\"token\": \"" + token + "\", \"platform\": \"" + platform + "\"}").exchange();
    }

    private MvcTestResult remove(UUID member, String token) {
        return mvc.delete().uri(TOKENS).with(member(member)).contentType(MediaType.APPLICATION_JSON)
                .content("{\"token\": \"" + token + "\"}").exchange();
    }

    private MvcTestResult changeSettings(UUID member, String body) {
        return mvc.put().uri(SETTINGS).with(member(member)).contentType(MediaType.APPLICATION_JSON).content(body).exchange();
    }

    private List<String> tokensOf(UUID member) {
        return jdbc.queryForList("SELECT token FROM notification.device_tokens WHERE member_id = ? ORDER BY token",
                String.class, member);
    }

    private static RequestPostProcessor member(UUID memberId) {
        return jwt().jwt(j -> j.subject(memberId.toString()));
    }
}
