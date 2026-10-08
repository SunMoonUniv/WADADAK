package com.wadadak.member;

import com.nimbusds.jwt.SignedJWT;
import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
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
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * member 단독 기동(다른 도메인 모듈 없이). 분리 가능성의 직접 증거다(개발 정책 10.6).
 * 소셜 검증은 로컬용 가짜 구현이라 토큰 문자열이 그대로 소셜 ID가 된다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class MemberModuleTests {

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JsonMapper jsonMapper;

    @Autowired
    MemberApi memberApi;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void signupThenLoginThenRefresh() throws Exception {
        JsonNode first = data(post("/login", login("kakao-flow")));
        assertThat(first.get("signupRequired").asBoolean()).isTrue();

        JsonNode tokens = data(post("/signup", signup(first.get("signupToken").asString(), "흐름러너", true)));
        String accessToken = tokens.get("accessToken").asString();
        UUID memberId = UUID.fromString(SignedJWT.parse(accessToken).getJWTClaimsSet().getSubject());

        // 인증을 통과하면 없는 경로라 404
        assertThat(mvc.get().uri("/api/v1/members/unknown").header("Authorization", "Bearer " + accessToken))
                .hasStatus(HttpStatus.NOT_FOUND);
        assertThat(memberApi.getProfiles(Set.of(memberId)))
                .containsExactly(new MemberProfile(memberId, "흐름러너", null, false));
        assertThat(jdbcTemplate.queryForMap(
                "SELECT bio, region_code, affiliation, running_experience FROM member.members WHERE id = ?", memberId))
                .containsEntry("bio", null)
                .containsEntry("region_code", "1129000000")
                .containsEntry("affiliation", "선문대학교")
                .containsEntry("running_experience", "MONTHS_6");

        JsonNode again = data(post("/login", login("kakao-flow")));
        assertThat(again.get("signupRequired").asBoolean()).isFalse();
        assertThat(again.get("tokens").get("accessToken").asString()).isNotBlank();

        String refreshToken = tokens.get("refreshToken").asString();
        assertThat(data(post("/refresh", refresh(refreshToken))).get("refreshToken").asString()).isNotEqualTo(refreshToken);
        assertThat(post("/refresh", refresh(refreshToken)))
                .hasStatus(HttpStatus.UNAUTHORIZED)
                .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-004");
    }

    @Test
    void logoutRevokesRefreshToken() throws Exception {
        String signupToken = data(post("/login", login("kakao-logout"))).get("signupToken").asString();
        String refreshToken = data(post("/signup", signup(signupToken, "로그아웃러너", true))).get("refreshToken").asString();

        assertThat(post("/logout", refresh(refreshToken))).hasStatusOk();
        assertThat(post("/refresh", refresh(refreshToken)))
                .hasStatus(HttpStatus.UNAUTHORIZED)
                .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-004");
    }

    @Test
    void signupTokenCannotCallApi() throws Exception {
        String signupToken = data(post("/login", login("kakao-signup-only"))).get("signupToken").asString();

        assertThat(mvc.get().uri("/api/v1/members/unknown").header("Authorization", "Bearer " + signupToken))
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    @Test
    void rejectsDuplicateNicknameIgnoringCase() throws Exception {
        String first = data(post("/login", login("kakao-dup-1"))).get("signupToken").asString();
        String second = data(post("/login", login("kakao-dup-2"))).get("signupToken").asString();
        data(post("/signup", signup(first, "Runner", true)));

        assertThat(post("/signup", signup(second, "runner", true)))
                .hasStatus(HttpStatus.CONFLICT)
                .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-006");
    }

    @Test
    void requiresAllMandatoryAgreements() throws Exception {
        String signupToken = data(post("/login", login("kakao-terms"))).get("signupToken").asString();

        assertThat(post("/signup", signup(signupToken, "약관러너", false)))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    @Test
    void showsWithdrawnMemberAsFixedName() throws Exception {
        String signupToken = data(post("/login", login("kakao-withdrawn"))).get("signupToken").asString();
        String accessToken = data(post("/signup", signup(signupToken, "떠난러너", true))).get("accessToken").asString();
        UUID memberId = UUID.fromString(SignedJWT.parse(accessToken).getJWTClaimsSet().getSubject());
        jdbcTemplate.update("UPDATE member.members SET status = 'WITHDRAWN', nickname = NULL, social_id = NULL WHERE id = ?", memberId);

        assertThat(memberApi.getProfiles(Set.of(memberId)))
                .containsExactly(new MemberProfile(memberId, MemberProfile.WITHDRAWN_NICKNAME, null, true));
    }

    @Test
    void rejectsMoreThanMaxIds() {
        Set<UUID> ids = Stream.generate(UUID::randomUUID).limit(MemberApi.MAX_IDS + 1).collect(Collectors.toSet());

        assertThatThrownBy(() -> memberApi.getProfiles(ids))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(MemberErrorCode.TOO_MANY_MEMBER_IDS));
    }

    private MvcTestResult post(String path, String body) {
        return mvc.post().uri("/api/v1/members/auth" + path).contentType(MediaType.APPLICATION_JSON).content(body).exchange();
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private static String login(String socialId) {
        return """
                {"provider": "KAKAO", "token": "%s"}""".formatted(socialId);
    }

    private static String refresh(String refreshToken) {
        return """
                {"refreshToken": "%s"}""".formatted(refreshToken);
    }

    private static String signup(String signupToken, String nickname, boolean agreeAll) {
        return """
                {
                  "signupToken": "%s",
                  "agreements": {"over14": true, "serviceTerms": true, "privacyPolicy": true,
                                 "locationTerms": %s, "profileInfo": true, "email": false},
                  "nickname": "%s",
                  "regionCode": "1129000000",
                  "affiliation": "선문대학교",
                  "runningExperience": "MONTHS_6"
                }""".formatted(signupToken, agreeAll, nickname);
    }
}
