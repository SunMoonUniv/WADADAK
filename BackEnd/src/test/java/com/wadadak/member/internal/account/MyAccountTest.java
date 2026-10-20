package com.wadadak.member.internal.account;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.event.member.MemberVisibilityChangedEvent;
import com.wadadak.member.internal.social.SocialAccount;
import com.wadadak.member.internal.social.SocialProvider;
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
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 내 정보 조회 · MY 설정(F13). member 단독 기동.
 *
 * <p>[읽는 법] 회원은 가입 API 대신 저장소로 바로 만든다. {@code jwt().jwt(j -> j.subject(...))}로
 * 그 회원이 로그인한 요청처럼 만들고, {@code AssertablePublishedEvents}로 공개 설정 이벤트가 나갔는지 본다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class MyAccountTest {

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JsonMapper jsonMapper;

    @Autowired
    MemberRepository memberRepository;

    @Autowired
    JdbcTemplate jdbc;

    /** 사진 주소만 흉내 낸다. 실제 저장소는 ObjectStorageTest가 확인한다. */
    @MockitoBean
    ObjectStorage storage;

    @BeforeEach
    void storage() {
        given(storage.url(anyString())).willAnswer(call -> "https://files.test/wadadak/" + call.getArgument(0));
    }

    @Test
    void showsMyProfileWithBodyInfoAndRegion() throws Exception {
        Member member = join("마이러너", "member/me.jpg", new BodyInfo(1998, 175, 68, Gender.MALE));

        JsonNode me = data(mvc.get().uri("/api/v1/members/me").with(as(member)).exchange());

        assertThat(me.get("memberId").asString()).isEqualTo(member.getId().toString());
        assertThat(me.get("nickname").asString()).isEqualTo("마이러너");
        assertThat(me.get("bio").asString()).isEqualTo("야간 러닝 좋아합니다");
        assertThat(me.get("region").get("code").asString()).isEqualTo("1129000000");
        assertThat(me.get("region").get("name").asString()).isEqualTo("성북구");
        assertThat(me.get("region").get("fullName").asString()).isEqualTo("서울특별시 성북구");
        assertThat(me.get("affiliation").asString()).isEqualTo("선문대학교");
        assertThat(me.get("runningExperience").asString()).isEqualTo("MONTHS_6");
        assertThat(me.get("profileImageUrl").asString()).isEqualTo("https://files.test/wadadak/member/me.jpg");
        assertThat(me.get("bodyInfo").get("birthYear").asInt()).isEqualTo(1998);
        assertThat(me.get("bodyInfo").get("gender").asString()).isEqualTo("MALE");
        assertThat(me.get("socialProvider").asString()).isEqualTo("KAKAO");
        assertThat(me.get("infoPublic").asBoolean()).isTrue();
        assertThat(me.get("profileSearchable").asBoolean()).isTrue();
    }

    @Test
    void showsNullForMissingPhotoAndBodyInfo() throws Exception {
        Member member = join("빈칸러너", null, null);

        JsonNode me = data(mvc.get().uri("/api/v1/members/me").with(as(member)).exchange());

        assertThat(me.get("profileImageUrl").isNull()).isTrue();
        assertThat(me.get("bodyInfo").isNull()).isTrue();
    }

    @Test
    void turningInfoPublicOffTellsOtherModulesWithNewVersion(AssertablePublishedEvents events) throws Exception {
        Member member = join("공개러너", null, null);

        JsonNode me = data(settings(member, false, true));

        assertThat(me.get("infoPublic").asBoolean()).isFalse();
        assertThat(me.get("profileSearchable").asBoolean()).isTrue();
        assertThat(jdbc.queryForObject("SELECT info_public FROM member.members WHERE id = ?", Boolean.class, member.getId()))
                .isFalse();
        // 가입 때 버전 0에서 한 번 바뀌어 1이다. 받는 쪽은 이보다 작은 버전의 이벤트를 버린다
        assertThat(events.ofType(MemberVisibilityChangedEvent.class).matching(e -> e.memberId().equals(member.getId())))
                .singleElement()
                .satisfies(e -> {
                    assertThat(e.visible()).isFalse();
                    assertThat(e.version()).isEqualTo(1);
                });
    }

    @Test
    void sendsNoEventWhenInfoPublicStaysTheSame(AssertablePublishedEvents events) throws Exception {
        Member member = join("검색러너", null, null);

        // 내 정보 공개는 그대로(켬)이고 프로필 검색 허용만 끈다
        JsonNode me = data(settings(member, true, false));

        assertThat(me.get("profileSearchable").asBoolean()).isFalse();
        assertThat(jdbc.queryForObject("SELECT profile_searchable FROM member.members WHERE id = ?", Boolean.class,
                member.getId())).isFalse();
        assertThat(events.ofType(MemberVisibilityChangedEvent.class).matching(e -> e.memberId().equals(member.getId())))
                .isEmpty();
    }

    @Test
    void requiresBothSettings() {
        Member member = join("빠진러너", null, null);

        MvcTestResult result = mvc.put().uri("/api/v1/members/me/settings").with(as(member))
                .contentType(MediaType.APPLICATION_JSON).content("""
                        {"infoPublic": false}""").exchange();

        assertThat(result).hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    @Test
    void withdrawnOrUnknownMemberMustLogInAgain() {
        Member withdrawn = join("떠난러너", null, null);
        jdbc.update("UPDATE member.members SET status = 'WITHDRAWN' WHERE id = ?", withdrawn.getId());

        assertThat(mvc.get().uri("/api/v1/members/me").with(as(withdrawn)).exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-002");
        assertThat(mvc.get().uri("/api/v1/members/me").with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString())))
                .exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-002");
        assertThat(settings(withdrawn, false, false))
                .hasStatus(HttpStatus.UNAUTHORIZED)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-002");
    }

    @Test
    void requiresLogin() {
        assertThat(mvc.get().uri("/api/v1/members/me").exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private Member join(String nickname, String photoKey, BodyInfo bodyInfo) {
        return memberRepository.save(Member.join(new SocialAccount(SocialProvider.KAKAO, "me-" + UUID.randomUUID()),
                nickname, "야간 러닝 좋아합니다", "1129000000", "선문대학교", RunningExperience.MONTHS_6, photoKey, bodyInfo));
    }

    private MvcTestResult settings(Member member, boolean infoPublic, boolean profileSearchable) {
        return mvc.put().uri("/api/v1/members/me/settings").with(as(member))
                .contentType(MediaType.APPLICATION_JSON).content("""
                        {"infoPublic": %s, "profileSearchable": %s}""".formatted(infoPublic, profileSearchable))
                .exchange();
    }

    /** 그 회원이 로그인한 요청처럼 만든다(토큰의 sub = 회원 ID). */
    private static RequestPostProcessor as(Member member) {
        return jwt().jwt(j -> j.subject(member.getId().toString()));
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }
}
