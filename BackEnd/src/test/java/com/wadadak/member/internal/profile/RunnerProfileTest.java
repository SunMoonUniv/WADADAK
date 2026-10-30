package com.wadadak.member.internal.profile;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.storage.ObjectStorage;
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

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 다른 러너 프로필(I3). member 단독 기동. 회원은 저장소로 바로 만든다. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RunnerProfileTest {

    private static final UUID REQUESTER = UUID.randomUUID();

    @Autowired
    MockMvcTester mvc;

    @Autowired
    MemberRepository memberRepository;

    @Autowired
    JdbcTemplate jdbc;

    @MockitoBean
    ObjectStorage storage;

    @BeforeEach
    void storage() {
        given(storage.url(anyString())).willAnswer(call -> "https://files.test/wadadak/" + call.getArgument(0));
    }

    @Test
    void showsProfileEvenIfPrivateAndNotSearchable() {
        Member runner = join("프로필러너", "member/runner.jpg");
        runner.changeSettings(false, false); // 내 정보 비공개 · 검색 비허용이어도 프로필은 보인다
        memberRepository.save(runner);

        MvcTestResult result = get(runner.getId());

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.memberId").isEqualTo(runner.getId().toString());
        assertThat(result).bodyJson().extractingPath("$.data.nickname").isEqualTo("프로필러너");
        assertThat(result).bodyJson().extractingPath("$.data.profileImageUrl")
                .isEqualTo("https://files.test/wadadak/member/runner.jpg");
        assertThat(result).bodyJson().extractingPath("$.data.region.name").isEqualTo("성북구");
        assertThat(result).bodyJson().extractingPath("$.data.runningExperience").isEqualTo("YEAR_3");
    }

    @Test
    void withdrawnOrUnknownRunnerIsNotFound() {
        Member withdrawn = join("떠난러너", null);
        jdbc.update("UPDATE member.members SET status = 'WITHDRAWN' WHERE id = ?", withdrawn.getId());

        assertThat(get(withdrawn.getId())).hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-011");
        assertThat(get(UUID.randomUUID())).hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("MEMBER-011");
    }

    private Member join(String nickname, String photoKey) {
        return memberRepository.save(Member.join(new SocialAccount(SocialProvider.KAKAO, "profile-" + UUID.randomUUID()),
                nickname, null, "1129000000", null, RunningExperience.YEAR_3, photoKey, null));
    }

    private MvcTestResult get(UUID memberId) {
        return mvc.get().uri("/api/v1/members/{memberId}", memberId)
                .with(jwt().jwt(j -> j.subject(REQUESTER.toString()))).exchange();
    }
}
