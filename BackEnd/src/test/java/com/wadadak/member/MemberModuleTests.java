package com.wadadak.member;

import com.nimbusds.jwt.SignedJWT;
import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.common.storage.PhotoUploads;
import com.wadadak.common.storage.UploadForm;
import com.wadadak.event.member.MemberRegionChangedEvent;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.modulith.test.AssertablePublishedEvents;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;

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

    /** 저장소와 폼 장부는 흉내만 낸다. 실제 업로드는 ObjectStorageTest, 장부는 PhotoUploadsTest가 확인한다. */
    @MockitoBean
    ObjectStorage storage;

    @MockitoBean
    PhotoUploads uploads;

    /** 폼으로 올라와 아직 저장하지 않은 사진 키. 저장(claim)하면 빠져서 다시 쓸 수 없다 */
    final Set<String> uploaded = new HashSet<>();

    @BeforeEach
    void storage() {
        given(uploads.claim(anyString(), anyString(), anyCollection())).willAnswer(call -> call.<Collection<String>>getArgument(2)
                .stream().allMatch(key -> key.startsWith(call.getArgument(0) + "/") && uploaded.remove(key)));
        given(storage.url(anyString())).willAnswer(call -> "https://files.test/wadadak/" + call.getArgument(0));
    }

    @Test
    void signupThenLoginThenRefresh(AssertablePublishedEvents events) throws Exception {
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
        assertThat(jdbcTemplate.queryForList(
                "SELECT type FROM member.agreements WHERE member_id = ? AND version = '1' AND agreed", String.class, memberId))
                .containsExactlyInAnyOrder("OVER_14", "SERVICE_TERMS", "PRIVACY_POLICY", "LOCATION_TERMS", "PROFILE_INFO");
        // 가입 때 정한 활동 지역은 이전 지역 없이 발행한다(ranking이 바로 반영).
        assertThat(events).contains(MemberRegionChangedEvent.class)
                .matching(e -> e.memberId().equals(memberId) && e.regionCode().equals("1129000000")
                        && e.previousRegionCode() == null && e.version() == 0);

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
    void rejectsRegionThatIsNotSigungu() throws Exception {
        String signupToken = data(post("/login", login("kakao-region"))).get("signupToken").asString();

        // 시·도(서울특별시), 읍·면·동(청운동), 없는 코드
        for (String regionCode : List.of("1100000000", "1111010100", "0000000000")) {
            assertThat(post("/signup", signup(signupToken, "지역러너", true, regionCode)))
                    .hasStatus(HttpStatus.BAD_REQUEST)
                    .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-007");
        }
        assertThat(jdbcTemplate.queryForObject(
                "SELECT count(*) FROM member.members WHERE social_id = 'kakao-region'", Integer.class)).isZero();
    }

    @Test
    void signsUpWithProfilePhoto() throws Exception {
        String signupToken = data(post("/login", login("kakao-photo"))).get("signupToken").asString();
        given(uploads.form("member", "KAKAO:kakao-photo"))
                .willReturn(new UploadForm("https://files.test/wadadak", "member/form.jpg", Map.of("policy", "p")));

        // 로그인 전이라 가입 토큰으로 업로드 폼을 받는다. 발급 횟수는 소셜 계정으로 센다
        assertThat(post("/photo-uploads", "{\"signupToken\": \"%s\"}".formatted(signupToken)))
                .hasStatusOk().bodyJson().extractingPath("$.data.key").isEqualTo("member/form.jpg");
        assertThat(post("/photo-uploads", "{\"signupToken\": \"broken\"}"))
                .hasStatus(HttpStatus.UNAUTHORIZED).bodyJson().extractingPath("$.code").isEqualTo("MEMBER-003");

        String photo = uploadedPhoto();
        String accessToken = data(post("/signup", signup(signupToken, "사진러너", true, "1129000000", photo)))
                .get("accessToken").asString();
        UUID memberId = UUID.fromString(SignedJWT.parse(accessToken).getJWTClaimsSet().getSubject());

        assertThat(memberApi.getProfiles(Set.of(memberId)))
                .containsExactly(new MemberProfile(memberId, "사진러너", "https://files.test/wadadak/" + photo, false));
    }

    @Test
    void rejectsMissingOtherModuleOrTakenProfilePhoto() throws Exception {
        String taken = uploadedPhoto();
        data(post("/signup", signup(data(post("/login", login("kakao-photo-owner"))).get("signupToken").asString(),
                "사진주인", true, "1129000000", taken)));
        String signupToken = data(post("/login", login("kakao-photo-borrower"))).get("signupToken").asString();

        // 올라오지 않은 키, 리뷰 사진 키, 남이 쓰는 키
        for (String photo : List.of("member/" + UUID.randomUUID() + ".jpg", "review/" + UUID.randomUUID() + ".jpg", taken)) {
            assertThat(post("/signup", signup(signupToken, "빌린사진", true, "1129000000", photo)))
                    .hasStatus(HttpStatus.BAD_REQUEST)
                    .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-008");
        }
        assertThat(jdbcTemplate.queryForObject(
                "SELECT count(*) FROM member.members WHERE social_id = 'kakao-photo-borrower'", Integer.class)).isZero();
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
        return signup(signupToken, nickname, agreeAll, "1129000000");
    }

    private static String signup(String signupToken, String nickname, boolean agreeAll, String regionCode) {
        return signup(signupToken, nickname, agreeAll, regionCode, null);
    }

    private static String signup(String signupToken, String nickname, boolean agreeAll, String regionCode, String photo) {
        return """
                {
                  "signupToken": "%s",
                  "agreements": {"over14": true, "serviceTerms": true, "privacyPolicy": true,
                                 "locationTerms": %s, "profileInfo": true},
                  "nickname": "%s",
                  "regionCode": "%s",
                  "affiliation": "선문대학교",
                  "runningExperience": "MONTHS_6",
                  "profileImageKey": %s
                }""".formatted(signupToken, agreeAll, nickname, regionCode, photo == null ? "null" : "\"" + photo + "\"");
    }

    /** 저장소에 올라온 프로필 사진 키 하나 */
    private String uploadedPhoto() {
        String key = "member/" + UUID.randomUUID() + ".jpg";
        uploaded.add(key);
        return key;
    }
}
