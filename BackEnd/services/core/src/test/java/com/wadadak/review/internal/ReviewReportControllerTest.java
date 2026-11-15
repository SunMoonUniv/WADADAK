package com.wadadak.review.internal;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.course.CourseApi;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 리뷰 신고 API(G2-1~G2-4)와 목록의 {@code reportedByMe}. 리뷰는 SQL로 직접 넣는다.
 * 기동 방식은 {@link ReviewControllerTest}와 같다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class ReviewReportControllerTest {

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    // review만 띄워서 member 모듈이 없다. 목록이 닉네임을 붙이려고 부르므로 빈 목록을 돌려주게 한다
    @MockitoBean
    MemberApi memberApi;

    // 운영자 리뷰 관리가 코스 이름을 받으려고 부른다. 이 테스트에서는 쓰지 않는다
    @MockitoBean
    CourseApi courseApi;

    @MockitoBean
    ObjectStorage storage;

    private UUID course;
    private UUID me;
    private UUID writer;
    private UUID review;

    @BeforeEach
    void setUp() {
        course = UUID.randomUUID();
        me = UUID.randomUUID();
        writer = UUID.randomUUID();
        review = review(writer);
        given(memberApi.getProfiles(any())).willReturn(List.of());
    }

    @Test
    void reportsOthersReviewAndListShowsReportedByMe() throws Exception {
        MvcTestResult result = report(me, review, Map.of("reason", "ADVERTISING", "detail", "  링크 광고예요  "));

        assertThat(result).hasStatusOk();
        Map<String, Object> row = jdbcTemplate.queryForMap(
                "SELECT reason, detail FROM review.review_reports WHERE review_id = ? AND reporter_member_id = ?", review, me);
        assertThat(row.get("reason")).isEqualTo("ADVERTISING");
        assertThat(row.get("detail")).isEqualTo("링크 광고예요"); // 앞뒤 공백은 지운다

        // 신고한 나에게만 true. 앱은 이 값으로 사유 화면 대신 바로 G2-4를 띄운다
        assertThat(card(me).get("reportedByMe").asBoolean()).isTrue();
        assertThat(card(UUID.randomUUID()).get("reportedByMe").asBoolean()).isFalse();
    }

    @Test
    void blankDetailIsStoredAsNull() {
        assertThat(report(me, review, Map.of("reason", "OTHER", "detail", "   "))).hasStatusOk();

        assertThat(jdbcTemplate.queryForObject("SELECT detail FROM review.review_reports WHERE review_id = ?", String.class, review))
                .isNull();
    }

    @Test
    void sameMemberCanReportOnlyOnce() {
        assertThat(report(me, review, Map.of("reason", "ABUSE"))).hasStatusOk();

        // 다른 기기에서 다시 신고해도 하나만 남고, 앱은 같은 G2-4 안내를 띄운다
        assertError(report(me, review, Map.of("reason", "PRIVACY")), HttpStatus.CONFLICT, "REVIEW-009");
        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM review.review_reports WHERE review_id = ?", Long.class, review))
                .isOne();
        // 다른 회원은 따로 신고할 수 있다
        assertThat(report(UUID.randomUUID(), review, Map.of("reason", "ABUSE"))).hasStatusOk();
    }

    @Test
    void cannotReportOwnOrMissingReview() {
        assertError(report(writer, review, Map.of("reason", "OTHER")), HttpStatus.FORBIDDEN, "REVIEW-008");
        assertError(report(me, UUID.randomUUID(), Map.of("reason", "OTHER")), HttpStatus.NOT_FOUND, "REVIEW-003");
    }

    @Test
    void rejectsInvalidRequest() {
        assertError(report(me, review, Map.of()), HttpStatus.BAD_REQUEST, "COMMON-001");                       // 사유 없음
        assertError(report(me, review, Map.of("reason", "SPAM")), HttpStatus.BAD_REQUEST, "COMMON-001");       // 없는 사유
        assertError(report(me, review, Map.of("reason", "OTHER", "detail", "가".repeat(101))),
                HttpStatus.BAD_REQUEST, "COMMON-001");                                                          // 100자 초과
    }

    @Test
    void reportKeepsReviewSnapshot() {
        assertThat(report(me, review, Map.of("reason", "ABUSE"))).hasStatusOk();

        // 운영자가 리뷰를 지운 뒤에도 무엇을 지웠는지 보이게 신고할 때의 리뷰를 저장한다
        Map<String, Object> row = jdbcTemplate.queryForMap(
                "SELECT course_id, review_member_id, review_rating, review_content, status FROM review.review_reports WHERE review_id = ?",
                review);
        assertThat(row).containsEntry("course_id", course).containsEntry("review_member_id", writer)
                .containsEntry("review_rating", 1).containsEntry("review_content", "광고) 러닝화 최저가")
                .containsEntry("status", "PENDING");
    }

    @Test
    void authorDeletingReviewDeletesOnlyPendingReports() {
        assertThat(report(me, review, Map.of("reason", "ABUSE"))).hasStatusOk();
        UUID handledReporter = UUID.randomUUID();
        assertThat(report(handledReporter, review, Map.of("reason", "OTHER"))).hasStatusOk();
        jdbcTemplate.update("UPDATE review.review_reports SET status = 'DISMISSED', handled_at = now() WHERE reporter_member_id = ?",
                handledReporter);

        assertThat(mvc.delete().uri("/api/v1/reviews/{reviewId}", review)
                .with(jwt().jwt(j -> j.subject(writer.toString()))).exchange()).hasStatusOk();

        // 리뷰가 없어졌으니 처리할 신고도 없다. 이미 처리한 신고는 기록으로 남는다
        assertThat(jdbcTemplate.queryForList("SELECT reporter_member_id FROM review.review_reports WHERE review_id = ?",
                UUID.class, review)).containsExactly(handledReporter);
    }

    /** 근거 기록 없이 리뷰 1건. */
    private UUID review(UUID member) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO review.reviews (id, course_id, member_id, source_run_record_id, rating, safety_rating,
                    road_rating, lighting_rating, amenity_rating, content, tags, best_progress_percent, created_at, updated_at)
                VALUES (?, ?, ?, ?, 1, 1, 1, 1, 1, '광고) 러닝화 최저가', '{}', 100, now(), now())""",
                id, course, member, UUID.randomUUID());
        return id;
    }

    private MvcTestResult report(UUID member, UUID reviewId, Map<String, String> body) {
        return mvc.post().uri("/api/v1/reviews/{reviewId}/reports", reviewId)
                .with(jwt().jwt(j -> j.subject(member.toString())))
                .contentType(MediaType.APPLICATION_JSON)
                .content(jsonMapper.writeValueAsString(body))
                .exchange();
    }

    /** 그 회원이 본 이 코스의 첫 리뷰 카드. */
    private JsonNode card(UUID viewer) throws Exception {
        MvcTestResult result = mvc.get().uri("/api/v1/reviews?courseId=" + course)
                .with(jwt().jwt(j -> j.subject(viewer.toString()))).exchange();
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data").get("content").get(0);
    }

    private static void assertError(MvcTestResult result, HttpStatus status, String code) {
        assertThat(result).hasStatus(status).bodyJson().extractingPath("$.code").isEqualTo(code);
    }
}
