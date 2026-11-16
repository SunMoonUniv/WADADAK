package com.wadadak.course.internal.mine;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.config.TimeConfig;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.convention.TestBean;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 스텁({@code app.stub.course-mine=true}) 데이터로 G4 · B7 API 형식을 확인한다. 스텁 코스는 {@link MyCoursesStub} 참고.
 * 지금은 2026-10-30(금) 12:00 Asia/Seoul로 고정한다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
@TestPropertySource(properties = "app.stub.course-mine=true")
class MyCourseControllerTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    MockMvcTester mvc;

    @TestBean
    Clock clock;

    static Clock clock() {
        return Clock.fixed(Instant.parse("2026-10-30T03:00:00Z"), TimeConfig.SEOUL);
    }

    @Test
    void listsExpiringSoonFirstThenLatest() {
        MvcTestResult result = mvc.get().uri("/api/v1/courses/mine").with(member()).exchange();

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.content[*].name").asArray().containsExactly(
                "성북천 벚꽃길 3K", "한강 야경 5K", "개운산 숲길 4K", "정릉천 물길 5K", "북악산 둘레길 6K", "안암 골목길 2K");
        // 성북천: 만료 D-1 · 최근 주행 29일 전 · 누적 214회
        assertThat(result).bodyJson().extractingPath("$.data.content[0].expiresAt").isEqualTo("2026-10-31T14:59:59Z");
        assertThat(result).bodyJson().extractingPath("$.data.content[0].lastCompletedOn").isEqualTo("2026-10-01");
        assertThat(result).bodyJson().extractingPath("$.data.content[0].completionCount").isEqualTo(214);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].tags").asArray().containsExactly("FLAT", "SHADE", "RESTROOM");
        assertThat(result).bodyJson().extractingPath("$.data.content[0].deleteAt").isNull();
        // 안암: 어제 만료돼 삭제 예정, 내일 00:00(Asia/Seoul) 삭제
        assertThat(result).bodyJson().extractingPath("$.data.content[5].status").isEqualTo("HIDDEN");
        assertThat(result).bodyJson().extractingPath("$.data.content[5].statusReason").isEqualTo("EXPIRED");
        assertThat(result).bodyJson().extractingPath("$.data.content[5].deleteAt").isEqualTo("2026-10-30T15:00:00Z");
        assertThat(result).bodyJson().extractingPath("$.data.nextCursor").isNull();
    }

    @Test
    void summaryCountsOnlyPublicCourses() {
        MvcTestResult result = mvc.get().uri("/api/v1/courses/mine/summary").with(member()).exchange();

        assertThat(result).bodyJson().extractingPath("$.data.courseCount").isEqualTo(5);
        assertThat(result).bodyJson().extractingPath("$.data.completionCount").isEqualTo(1_480);
        assertThat(result).bodyJson().extractingPath("$.data.expiringSoonCount").isEqualTo(1);
    }

    @Test
    void editReturnsChangedCard() {
        MvcTestResult result = edit(MyCoursesStub.SEONGBUK_ID, "  성북천   밤벚꽃길 ", "[\"RESTROOM\", \"FLAT\"]");

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.name").isEqualTo("성북천 밤벚꽃길");
        assertThat(result).bodyJson().extractingPath("$.data.difficulty").isEqualTo("MEDIUM");
        assertThat(result).bodyJson().extractingPath("$.data.tags").asArray().containsExactly("FLAT", "RESTROOM");
        assertThat(result).bodyJson().extractingPath("$.data.completionCount").isEqualTo(214);
        assertThat(edit(MyCoursesStub.SEONGBUK_ID, "성북천 벚꽃길 3K", "[]")).as("지금 이름 그대로").hasStatusOk();
    }

    @Test
    void editRejectsTakenNameAndCoursesICannotEdit() {
        assertThat(edit(MyCoursesStub.SEONGBUK_ID, "한강야경 5k", "[]")).hasStatus(HttpStatus.CONFLICT)
                .bodyJson().extractingPath("$.code").isEqualTo("COURSE-006");
        assertThat(edit(MyCoursesStub.ANAM_ID, "안암 새 골목길", "[]")).hasStatus(HttpStatus.CONFLICT)
                .bodyJson().extractingPath("$.code").isEqualTo("COURSE-002");
        assertThat(edit(MyCoursesStub.OTHERS_COURSE_ID, "남의 코스 이름", "[]")).hasStatus(HttpStatus.FORBIDDEN)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-003");
        assertThat(edit(UUID.randomUUID(), "없는 코스 이름", "[]")).hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("COURSE-001");
        assertThat(edit(MyCoursesStub.SEONGBUK_ID, "성", "[]")).hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    @Test
    void deleteHidesCourseUntilTomorrow() {
        MvcTestResult result = delete(MyCoursesStub.HANGANG_ID);

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.status").isEqualTo("HIDDEN");
        assertThat(result).bodyJson().extractingPath("$.data.statusReason").isEqualTo("USER_DELETED");
        assertThat(result).bodyJson().extractingPath("$.data.deleteAt").isEqualTo("2026-10-31T03:00:00Z");
        // 이미 삭제 예정이면 그대로 돌려준다
        assertThat(delete(MyCoursesStub.ANAM_ID)).bodyJson().extractingPath("$.data.statusReason").isEqualTo("EXPIRED");
        assertThat(delete(MyCoursesStub.OTHERS_COURSE_ID)).hasStatus(HttpStatus.FORBIDDEN);
    }

    private MvcTestResult edit(UUID courseId, String name, String tags) {
        return mvc.put().uri("/api/v1/courses/{courseId}", courseId).with(member()).contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\": \"" + name + "\", \"difficulty\": \"MEDIUM\", \"tags\": " + tags + "}").exchange();
    }

    private MvcTestResult delete(UUID courseId) {
        return mvc.delete().uri("/api/v1/courses/{courseId}", courseId).with(member()).exchange();
    }

    private static RequestPostProcessor member() {
        return jwt().jwt(j -> j.subject(UUID.randomUUID().toString()));
    }
}
