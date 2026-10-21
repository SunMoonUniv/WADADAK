package com.wadadak.member.internal.account;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.common.storage.PhotoUploads;
import com.wadadak.common.storage.UploadForm;
import com.wadadak.event.member.MemberRegionChangedEvent;
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

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.Year;
import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 내 정보 조회 · MY 설정 · 프로필 편집(F13). member 단독 기동.
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

    @Autowired
    Clock clock;

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
        assertThat(me.get("profileImageKey").asString()).isEqualTo("member/me.jpg");
        assertThat(me.get("profileImageUrl").asString()).isEqualTo("https://files.test/wadadak/member/me.jpg");
        assertThat(me.get("nicknameChangeableAt").isNull()).isTrue(); // 가입 뒤 한 번도 안 바꿨다
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
        Member withdrawn = join("탈퇴한마이러너", null, null);
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
    void editsProfileAndTellsRankingAboutNewRegion(AssertablePublishedEvents events) throws Exception {
        Member member = join("편집러너", null, null);
        String photo = uploadedPhoto();
        int birthYear = Year.now(clock).getValue() - 20;

        JsonNode me = data(edit(member, "새이름러너", "1111000000", photo, bodyInfo(birthYear)));

        assertThat(me.get("nickname").asString()).isEqualTo("새이름러너");
        assertThat(me.get("bio").asString()).isEqualTo("새벽 러닝으로 바꿨어요");
        assertThat(me.get("region").get("name").asString()).isEqualTo("종로구");
        assertThat(me.get("affiliation").isNull()).isTrue(); // 빈 소속은 지운다
        assertThat(me.get("runningExperience").asString()).isEqualTo("YEAR_1");
        assertThat(me.get("profileImageKey").asString()).isEqualTo(photo);
        assertThat(me.get("bodyInfo").get("birthYear").asInt()).isEqualTo(birthYear);
        // 오늘(Asia/Seoul) 바꿨으니 30일 뒤 00:00부터 다시 바꿀 수 있다
        Instant changeableAt = LocalDate.now(clock.withZone(TimeConfig.SEOUL)).plusDays(30)
                .atStartOfDay(TimeConfig.SEOUL).toInstant();
        assertThat(Instant.parse(me.get("nicknameChangeableAt").asString())).isEqualTo(changeableAt);
        // 신체 정보를 처음 넣었으니 동의 이력이 한 줄 생긴다
        assertThat(bodyInfoConsents(member)).containsExactly(true);
        // 가입 때 버전 0에서 한 번 바뀌어 1이다. ranking은 다음 주부터 종로구에 넣는다
        assertThat(events.ofType(MemberRegionChangedEvent.class).matching(e -> e.memberId().equals(member.getId())))
                .singleElement()
                .satisfies(e -> {
                    assertThat(e.regionCode()).isEqualTo("1111000000");
                    assertThat(e.previousRegionCode()).isEqualTo("1129000000");
                    assertThat(e.version()).isEqualTo(1);
                });
    }

    @Test
    void sendsNoRegionEventWhenRegionStaysTheSame(AssertablePublishedEvents events) throws Exception {
        Member member = join("그대로러너", null, null);

        data(edit(member, "그대로러너", "1129000000", null, null));

        assertThat(events.ofType(MemberRegionChangedEvent.class).matching(e -> e.memberId().equals(member.getId())))
                .isEmpty();
        assertThat(bodyInfoConsents(member)).isEmpty(); // 신체 정보는 계속 없음이라 이력도 없다
    }

    @Test
    void nicknameChangesOnlyOnceIn30Days() throws Exception {
        Member member = join("한달러너", null, null);
        LocalDate today = LocalDate.now(clock.withZone(TimeConfig.SEOUL));

        // 29일 전에 바꿨으면 아직 안 된다. 닉네임만 그대로 두면 다른 칸은 고칠 수 있다
        changedNicknameOn(member, today.minusDays(29));
        assertThat(edit(member, "다른이름", "1129000000", null, null))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-010");
        JsonNode same = data(edit(member, "한달러너", "1129000000", null, null));
        assertThat(Instant.parse(same.get("nicknameChangeableAt").asString()))
                .isEqualTo(today.plusDays(1).atStartOfDay(TimeConfig.SEOUL).toInstant());

        // 30일 전 밤늦게 바꿨어도 날짜로 세서 오늘 0시부터 바꿀 수 있다
        changedNicknameOn(member, today.minusDays(30));
        assertThat(data(edit(member, "다른이름", "1129000000", null, null)).get("nickname").asString())
                .isEqualTo("다른이름");
    }

    @Test
    void rejectsTakenNicknameButAllowsChangingOnlyCaseOfMine() throws Exception {
        join("RunnerA", null, null);
        Member member = join("RunnerB", null, null);

        assertThat(edit(member, "runnera", "1129000000", null, null))
                .hasStatus(HttpStatus.CONFLICT)
                .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-006");
        assertThat(data(edit(member, "runnerb", "1129000000", null, null)).get("nickname").asString())
                .isEqualTo("runnerb");
    }

    @Test
    void replacesKeepsAndRemovesPhoto() throws Exception {
        Member member = join("사진교체러너", "member/old.jpg", null);

        // 그대로 두면 다시 받지도 지우지도 않는다
        data(edit(member, "사진교체러너", "1129000000", "member/old.jpg", null));
        verify(uploads, never()).claim(anyString(), anyString(), anyCollection());
        verify(storage, never()).deleteAfterCommit(anyCollection());

        // 새 사진으로 바꾸면 예전 파일을 지운다
        String photo = uploadedPhoto();
        data(edit(member, "사진교체러너", "1129000000", photo, null));
        verify(storage).deleteAfterCommit(List.of("member/old.jpg"));

        // 사진을 지우면 지금 파일을 지운다
        JsonNode me = data(edit(member, "사진교체러너", "1129000000", null, null));
        assertThat(me.get("profileImageUrl").isNull()).isTrue();
        verify(storage).deleteAfterCommit(List.of(photo));
    }

    @Test
    void turningBodyInfoOffClearsItAndRecordsConsent() throws Exception {
        Member member = join("신체정보러너", null, new BodyInfo(1998, 175, 68, Gender.MALE));

        // 동의를 켠 채 값만 바꾸면 이력은 그대로다
        data(edit(member, "신체정보러너", "1129000000", null, bodyInfo(1998)));
        assertThat(bodyInfoConsents(member)).isEmpty();

        JsonNode me = data(edit(member, "신체정보러너", "1129000000", null, null));

        assertThat(me.get("bodyInfo").isNull()).isTrue();
        assertThat(jdbc.queryForMap("SELECT birth_year, height_cm, weight_kg, gender FROM member.members WHERE id = ?",
                member.getId()))
                .containsEntry("birth_year", null).containsEntry("height_cm", null)
                .containsEntry("weight_kg", null).containsEntry("gender", null);
        assertThat(bodyInfoConsents(member)).containsExactly(false);
    }

    @Test
    void rejectsBadRegionPhotoOrBirthYear() {
        Member member = join("규칙러너", null, null);

        assertError(edit(member, "규칙러너", "1100000000", null, null), "MEMBER-007"); // 시·도는 안 된다
        assertError(edit(member, "규칙러너", "1129000000", "member/" + UUID.randomUUID() + ".jpg", null),
                "MEMBER-008"); // 내가 받은 폼으로 올리지 않은 키
        assertError(edit(member, "규칙러너", "1129000000", null, bodyInfo(Year.now(clock).getValue() - 14)),
                "MEMBER-009"); // 만 14세 이상이 확실하지 않은 해
        assertThat(jdbc.queryForObject("SELECT version FROM member.members WHERE id = ?", Long.class, member.getId()))
                .isZero(); // 아무것도 바뀌지 않았다
    }

    @Test
    void givesPhotoUploadFormForMe() throws Exception {
        Member member = join("폼러너", null, null);
        UploadForm form = new UploadForm("https://files.test/wadadak", "member/new.jpg", Map.of("policy", "p"));
        given(uploads.form("member", member.getId().toString())).willReturn(form);

        JsonNode data = data(mvc.post().uri("/api/v1/members/me/photo-uploads").with(as(member)).exchange());

        assertThat(data.get("key").asString()).isEqualTo("member/new.jpg");
    }

    @Test
    void requiresLogin() {
        assertThat(mvc.get().uri("/api/v1/members/me").exchange()).hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private Member join(String nickname, String photoKey, BodyInfo bodyInfo) {
        return memberRepository.save(Member.join(new SocialAccount(SocialProvider.KAKAO, "me-" + UUID.randomUUID()),
                nickname, "야간 러닝 좋아합니다", "1129000000", "선문대학교", RunningExperience.MONTHS_6, photoKey, bodyInfo));
    }

    /** F6 저장. 소개 · 소속 · 러닝 경력은 늘 같은 값으로 보낸다(빈 소속은 지워진다) */
    private MvcTestResult edit(Member member, String nickname, String regionCode, String photo, String bodyInfo) {
        return mvc.put().uri("/api/v1/members/me").with(as(member))
                .contentType(MediaType.APPLICATION_JSON).content("""
                        {
                          "nickname": "%s",
                          "bio": "새벽 러닝으로 바꿨어요",
                          "regionCode": "%s",
                          "affiliation": "  ",
                          "runningExperience": "YEAR_1",
                          "profileImageKey": %s,
                          "bodyInfo": %s
                        }""".formatted(nickname, regionCode, photo == null ? "null" : "\"" + photo + "\"", bodyInfo))
                .exchange();
    }

    private static String bodyInfo(int birthYear) {
        return """
                {"birthYear": %d, "heightCm": 180, "weightKg": 70, "gender": "MALE"}""".formatted(birthYear);
    }

    private String uploadedPhoto() {
        String key = "member/" + UUID.randomUUID() + ".jpg";
        uploaded.add(key);
        return key;
    }

    /** 그날(Asia/Seoul) 밤 23시에 닉네임을 바꾼 것으로 만든다 */
    private void changedNicknameOn(Member member, LocalDate day) {
        jdbc.update("UPDATE member.members SET nickname_changed_at = ? WHERE id = ?",
                Timestamp.from(day.atTime(23, 0).atZone(TimeConfig.SEOUL).toInstant()), member.getId());
    }

    /** 프로필 편집으로 쌓인 신체 정보 동의 이력(이 테스트는 회원을 저장소로 만들어 가입 때 행이 없다) */
    private List<Boolean> bodyInfoConsents(Member member) {
        return jdbc.queryForList("SELECT agreed FROM member.agreements WHERE member_id = ? AND type = 'BODY_INFO' "
                + "ORDER BY created_at", Boolean.class, member.getId());
    }

    private static void assertError(MvcTestResult result, String code) {
        assertThat(result).hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo(code);
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
