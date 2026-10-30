package com.wadadak.member.internal.search;

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
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 러너 검색(G7). member 단독 기동. 회원은 저장소로 바로 만들고, 테스트마다 다른 닉네임 앞부분을 써서 서로 걸리지 않게 한다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RunnerSearchTest {

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JsonMapper jsonMapper;

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
    void findsSearchableRunnersByNicknameIncludingMe() throws Exception {
        Member me = join("찾기본인", null);
        Member alpha = join("찾기Alpha", "member/alpha.jpg");
        Member runner = join("찾기러너");
        Member hidden = join("찾기숨김");
        hidden.changeSettings(true, false); // 프로필 검색 허용을 껐다
        memberRepository.save(hidden);
        Member withdrawn = join("찾기탈퇴");
        jdbc.update("UPDATE member.members SET status = 'WITHDRAWN' WHERE id = ?", withdrawn.getId());
        Member privateRunner = join("찾기비공개");
        privateRunner.changeSettings(false, true); // 내 정보 비공개여도 검색에는 나온다
        memberRepository.save(privateRunner);
        join("다른찾러너");

        JsonNode data = search(me, "찾 기", null, null); // 공백은 보지 않는다

        assertThat(data.get("totalCount").asInt()).isEqualTo(4);
        assertThat(data.get("nextCursor").isNull()).isTrue();
        assertThat(memberIds(data)).containsExactlyInAnyOrder(me.getId(), alpha.getId(), runner.getId(), privateRunner.getId());
        JsonNode mine = row(data, me);
        assertThat(mine.get("mine").asBoolean()).isTrue();
        assertThat(mine.get("profileImageUrl").isNull()).isTrue();
        JsonNode other = row(data, alpha);
        assertThat(other.get("mine").asBoolean()).isFalse();
        assertThat(other.get("nickname").asString()).isEqualTo("찾기Alpha");
        assertThat(other.get("profileImageUrl").asString()).isEqualTo("https://files.test/wadadak/member/alpha.jpg");
        assertThat(other.get("region").get("name").asString()).isEqualTo("성북구");
        assertThat(other.get("runningExperience").asString()).isEqualTo("YEAR_1");
    }

    @Test
    void ignoresCase() throws Exception {
        Member me = join("대소Alpha");

        JsonNode data = search(me, "대소ALP", null, null);

        assertThat(memberIds(data)).containsExactly(me.getId());
    }

    @Test
    void pagesInSameOrderEveryTime() throws Exception {
        Member me = join("쪽나눔1");
        join("쪽나눔2");
        join("쪽나눔3");

        JsonNode first = search(me, "쪽나눔", null, 2);
        JsonNode second = search(me, "쪽나눔", first.get("nextCursor").asString(), 2);

        assertThat(first.get("totalCount").asInt()).isEqualTo(3);
        assertThat(second.get("totalCount").asInt()).isEqualTo(3);
        assertThat(first.get("nextCursor").asString()).isEqualTo("2");
        assertThat(second.get("nextCursor").isNull()).isTrue();
        List<UUID> all = new ArrayList<>(memberIds(first));
        all.addAll(memberIds(second));
        assertThat(all).doesNotHaveDuplicates().hasSize(3);
        assertThat(memberIds(search(me, "쪽나눔", null, 3))).containsExactlyElementsOf(all);
    }

    @Test
    void rejectsQueryShorterThanTwoLetters() {
        Member me = join("짧은검색");

        MvcTestResult result = mvc.get().uri("/api/v1/members/search").param("query", " 짧 ").with(as(me)).exchange();

        assertThat(result).hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    private Member join(String nickname) {
        return join(nickname, null);
    }

    private Member join(String nickname, String photoKey) {
        return memberRepository.save(Member.join(new SocialAccount(SocialProvider.KAKAO, "search-" + UUID.randomUUID()),
                nickname, null, "1129000000", null, RunningExperience.YEAR_1, photoKey, null));
    }

    private JsonNode search(Member requester, String query, String cursor, Integer size) throws Exception {
        var request = mvc.get().uri("/api/v1/members/search").param("query", query).with(as(requester));
        if (cursor != null) {
            request = request.param("cursor", cursor);
        }
        if (size != null) {
            request = request.param("size", size.toString());
        }
        MvcTestResult result = request.exchange();
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private static List<UUID> memberIds(JsonNode data) {
        List<UUID> ids = new ArrayList<>();
        data.get("content").forEach(row -> ids.add(UUID.fromString(row.get("memberId").asString())));
        return ids;
    }

    private static JsonNode row(JsonNode data, Member member) {
        for (JsonNode row : data.get("content")) {
            if (row.get("memberId").asString().equals(member.getId().toString())) {
                return row;
            }
        }
        throw new AssertionError("no row for " + member.getNickname());
    }

    private static RequestPostProcessor as(Member member) {
        return jwt().jwt(j -> j.subject(member.getId().toString()));
    }
}
