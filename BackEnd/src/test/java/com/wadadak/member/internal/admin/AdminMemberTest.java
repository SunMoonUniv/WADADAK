package com.wadadak.member.internal.admin;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.member.internal.account.Agreement;
import com.wadadak.member.internal.account.AgreementRepository;
import com.wadadak.member.internal.account.BodyInfo;
import com.wadadak.member.internal.account.Gender;
import com.wadadak.member.internal.account.Member;
import com.wadadak.member.internal.account.MemberRepository;
import com.wadadak.member.internal.account.RunningExperience;
import com.wadadak.member.internal.social.SocialAccount;
import com.wadadak.member.internal.social.SocialProvider;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 운영자 회원 관리(ADM-1 · ADM-1-1). member 단독 기동, 운영자 계정은 application-test.yml의 test-admin이다.
 * 다른 테스트가 넣은 회원도 같은 DB에 있어서, 목록은 이 테스트가 넣은 회원만 골라 보고 숫자 카드는 늘어난 만큼만 본다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class AdminMemberTest {

    @Autowired
    MockMvcTester mvc;

    @Autowired
    MemberRepository memberRepository;

    @Autowired
    AgreementRepository agreementRepository;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    JsonMapper jsonMapper;

    @MockitoBean
    ObjectStorage storage;

    @BeforeEach
    void storage() {
        given(storage.url(anyString())).willAnswer(call -> "https://files.test/wadadak/" + call.getArgument(0));
    }

    @Test
    void onlyAdminAccountCanCall() {
        assertThat(mvc.get().uri("/api/v1/admin/members/stats").exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(mvc.get().uri("/api/v1/admin/members/stats").with(jwt()).exchange()).hasStatus(HttpStatus.FORBIDDEN);
        assertThat(admin("/api/v1/admin/members/stats")).hasStatusOk();
    }

    @Test
    void statsCountActiveMembersOnly() throws Exception {
        JsonNode before = data(admin("/api/v1/admin/members/stats"));
        join(SocialProvider.KAKAO, RunningExperience.YEAR_1, null);
        Member withdrawn = join(SocialProvider.GOOGLE, RunningExperience.BEGINNER, null);
        withdraw(withdrawn);

        JsonNode after = data(admin("/api/v1/admin/members/stats"));

        // 오늘 가입한 회원은 이번 주 · 이번 달에도 들어간다. 탈퇴 회원은 세지 않는다
        assertThat(after.get("totalMembers").asLong() - before.get("totalMembers").asLong()).isOne();
        assertThat(after.get("weekJoined").asLong() - before.get("weekJoined").asLong()).isOne();
        assertThat(after.get("monthJoined").asLong() - before.get("monthJoined").asLong()).isOne();
    }

    @Test
    void listFiltersAndHidesWithdrawn() throws Exception {
        Member kakao = join(SocialProvider.KAKAO, RunningExperience.YEAR_3, "member/me.jpg");
        Member google = join(SocialProvider.GOOGLE, RunningExperience.YEAR_3, null);
        Member withdrawn = join(SocialProvider.KAKAO, RunningExperience.YEAR_3, null);
        withdraw(withdrawn);

        JsonNode rows = data(admin("/api/v1/admin/members?socialProvider=KAKAO&runningExperience=YEAR_3&size=100")).get("content");

        JsonNode row = row(rows, kakao.getId());
        assertThat(row.get("nickname").asString()).isEqualTo(kakao.getNickname());
        assertThat(row.get("region").get("name").asString()).isEqualTo("성북구");
        assertThat(row.get("affiliation").asString()).isEqualTo("선문대학교 러닝 동아리");
        assertThat(row.get("profileImageUrl").asString()).isEqualTo("https://files.test/wadadak/member/me.jpg");
        assertThat(row(rows, google.getId())).isNull();    // 가입 방식이 다르다
        assertThat(row(rows, withdrawn.getId())).isNull(); // 탈퇴
    }

    @Test
    void detailShowsAllColumnsAndLatestAgreements() throws Exception {
        Member member = join(SocialProvider.KAKAO, RunningExperience.YEAR_1, null);
        agreementRepository.saveAll(Agreement.signup(member.getId(), true));
        agreementRepository.save(Agreement.bodyInfo(member.getId(), false)); // 나중에 신체 정보 동의를 껐다

        JsonNode detail = data(admin("/api/v1/admin/members/" + member.getId()));

        assertThat(detail.get("socialId").asString()).startsWith("admin-");
        assertThat(detail.get("regionCode").asString()).isEqualTo("1129000000");
        assertThat(detail.get("bodyInfo").get("heightCm").asInt()).isEqualTo(175);
        assertThat(detail.get("nicknameChangedAt").isNull()).isTrue();
        JsonNode agreements = detail.get("agreements");
        assertThat(agreements).hasSize(6);
        assertThat(agreements.get(0).get("type").asString()).isEqualTo("OVER_14");
        assertThat(agreements.get(5).get("type").asString()).isEqualTo("BODY_INFO");
        assertThat(agreements.get(5).get("agreed").asBoolean()).isFalse(); // 가장 최근 동의
    }

    @Test
    void withdrawnOrUnknownMemberIsNotFound() {
        Member withdrawn = join(SocialProvider.KAKAO, RunningExperience.BEGINNER, null);
        withdraw(withdrawn);

        assertThat(admin("/api/v1/admin/members/" + withdrawn.getId())).hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-011");
        assertThat(admin("/api/v1/admin/members/" + UUID.randomUUID())).hasStatus(HttpStatus.NOT_FOUND);
    }

    @Test
    void rejectsInvalidRequest() {
        assertThat(admin("/api/v1/admin/members?size=101")).hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
        assertThat(admin("/api/v1/admin/members?socialProvider=NAVER")).hasStatus(HttpStatus.BAD_REQUEST);
    }

    private Member join(SocialProvider provider, RunningExperience experience, String photoKey) {
        String suffix = UUID.randomUUID().toString().substring(0, 8);
        return memberRepository.save(Member.join(new SocialAccount(provider, "admin-" + suffix), "관리" + suffix,
                "퇴근하고 달리는 직장인", "1129000000", "선문대학교 러닝 동아리", experience, photoKey,
                new BodyInfo(1999, 175, 68, Gender.MALE)));
    }

    private void withdraw(Member member) {
        jdbc.update("UPDATE member.members SET status = 'WITHDRAWN', nickname = NULL, social_id = NULL WHERE id = ?",
                member.getId());
    }

    private MvcTestResult admin(String uri) {
        return mvc.get().uri(uri).with(httpBasic("test-admin", "test-admin-password")).exchange();
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private static JsonNode row(JsonNode rows, UUID memberId) {
        return rows.valueStream().filter(r -> r.get("memberId").asString().equals(memberId.toString())).findFirst().orElse(null);
    }
}
