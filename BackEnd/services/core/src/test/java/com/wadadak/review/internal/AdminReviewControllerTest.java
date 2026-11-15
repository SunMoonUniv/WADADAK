package com.wadadak.review.internal;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.course.CourseApi;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
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

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.StreamSupport;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 운영자 리뷰 관리 API(ADM-2 · ADM-2-1 · ADM-2-2). 운영자 계정은 application-test.yml의 test-admin이다.
 * 다른 테스트가 넣은 리뷰도 같은 DB에 있어서, 목록은 이 테스트가 넣은 리뷰만 골라 보고 숫자 카드는 늘어난 만큼만 본다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class AdminReviewControllerTest {

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    // review만 띄워서 member · course 모듈이 없다. 이름은 가짜로 돌려준다
    @MockitoBean
    MemberApi memberApi;

    @MockitoBean
    CourseApi courseApi;

    @MockitoBean
    ObjectStorage storage;

    private UUID course;
    private UUID writer;
    private UUID review;

    @BeforeEach
    void setUp() {
        course = UUID.randomUUID();
        writer = UUID.randomUUID();
        review = review(writer, 1);
        given(courseApi.getNames(any())).willReturn(Map.of(course, "천안천 산책로"));
        given(memberApi.getProfiles(any())).willAnswer(call -> {
            Iterable<UUID> ids = call.getArgument(0);
            return StreamSupport.stream(ids.spliterator(), false)
                    .map(id -> new MemberProfile(id, id.equals(writer) ? "천안야간런" : "신고자", null, false))
                    .toList();
        });
    }

    @Test
    void onlyAdminAccountCanCall() {
        MvcTestResult anonymous = mvc.get().uri("/api/v1/admin/reviews/stats").exchange();
        assertError(anonymous, HttpStatus.UNAUTHORIZED, "COMMON-002");
        // 브라우저가 자체 로그인 창을 띄우지 않게 Basic 안내 헤더를 보내지 않는다
        assertThat(anonymous.getResponse().getHeader(HttpHeaders.WWW_AUTHENTICATE)).isNull();
        assertThat(mvc.get().uri("/api/v1/admin/reviews/stats").with(httpBasic("test-admin", "wrong")).exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED);
        // 회원 로그인(JWT)으로는 들어올 수 없다. 운영자 체인은 Bearer 토큰을 읽지 않는다
        assertThat(mvc.get().uri("/api/v1/admin/reviews/stats").header(HttpHeaders.AUTHORIZATION, "Bearer member-token").exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(admin(mvc.get().uri("/api/v1/admin/reviews/stats"))).hasStatusOk();
    }

    @Test
    void statsCountReviewsAndReports() throws Exception {
        JsonNode before = data(admin(mvc.get().uri("/api/v1/admin/reviews/stats")));
        report(review, "ADVERTISING");
        report(review, "ABUSE");

        JsonNode after = data(admin(mvc.get().uri("/api/v1/admin/reviews/stats")));

        assertThat(after.get("pendingReviews").asLong() - before.get("pendingReviews").asLong()).isOne(); // 리뷰 하나에 한 줄
        assertThat(after.get("todayReports").asLong() - before.get("todayReports").asLong()).isEqualTo(2);
        assertThat(after.get("totalReports").asLong() - before.get("totalReports").asLong()).isEqualTo(2);
        assertThat(after.get("totalReviews").asLong()).isPositive();
    }

    @Test
    void reviewListFiltersByRatingAndShowsNames() throws Exception {
        UUID fiveStar = review(UUID.randomUUID(), 5);
        report(review, "ADVERTISING");

        JsonNode oneStar = row(admin(mvc.get().uri("/api/v1/admin/reviews?rating=1&days=7&size=100")), review);
        assertThat(oneStar.get("courseName").asString()).isEqualTo("천안천 산책로");
        assertThat(oneStar.get("authorNickname").asString()).isEqualTo("천안야간런");
        assertThat(oneStar.get("pendingReportCount").asInt()).isOne();
        assertThat(row(admin(mvc.get().uri("/api/v1/admin/reviews?rating=1&size=100")), fiveStar)).isNull();
    }

    @Test
    void reportListGroupsByReviewAndFilters() throws Exception {
        report(review, "ABUSE");
        report(review, "ADVERTISING");

        JsonNode group = row(admin(mvc.get().uri("/api/v1/admin/review-reports?status=PENDING&size=100")), review);
        assertThat(group.get("reportCount").asInt()).isEqualTo(2);
        assertThat(group.get("reasons").valueStream().map(JsonNode::asString)).containsExactly("ADVERTISING", "ABUSE");
        assertThat(group.get("content").asString()).isEqualTo("광고) 러닝화 최저가");
        assertThat(group.get("courseName").asString()).isEqualTo("천안천 산책로");
        assertThat(row(admin(mvc.get().uri("/api/v1/admin/review-reports?reason=PRIVACY&size=100")), review)).isNull();
        assertThat(row(admin(mvc.get().uri("/api/v1/admin/review-reports?status=DISMISSED&size=100")), review)).isNull();
    }

    @Test
    void dismissClosesPendingReportsOnce() throws Exception {
        report(review, "OTHER");

        assertThat(handle(review, "DISMISSED", "  광고 아님  ")).hasStatusOk();

        JsonNode detail = data(admin(mvc.get().uri("/api/v1/admin/reviews/{id}", review)));
        assertThat(detail.get("status").asString()).isEqualTo("DISMISSED");
        assertThat(detail.get("memo").asString()).isEqualTo("광고 아님");
        assertThat(detail.get("reviewDeleted").asBoolean()).isFalse();
        assertThat(detail.get("safetyRating").asInt()).isOne(); // 항목 평가도 보인다
        assertThat(detail.get("reports").get(0).get("reporterNickname").asString()).isEqualTo("신고자");
        // 더 처리할 대기 신고가 없다
        assertError(handle(review, "DISMISSED", null), HttpStatus.CONFLICT, "REVIEW-010");
        // 문제 없음 뒤에 새 신고가 오면 다시 대기다
        report(review, "ABUSE");
        assertThat(data(admin(mvc.get().uri("/api/v1/admin/reviews/{id}", review))).get("status").asString()).isEqualTo("PENDING");
    }

    @Test
    void deleteRemovesReviewButKeepsReportRecord() throws Exception {
        report(review, "ADVERTISING");

        assertThat(handle(review, "DELETED", "광고 링크")).hasStatusOk();

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM review.reviews WHERE id = ?", Long.class, review)).isZero();
        JsonNode detail = data(admin(mvc.get().uri("/api/v1/admin/reviews/{id}", review)));
        assertThat(detail.get("reviewDeleted").asBoolean()).isTrue();
        assertThat(detail.get("status").asString()).isEqualTo("DELETED");
        assertThat(detail.get("content").asString()).isEqualTo("광고) 러닝화 최저가"); // 신고 때 저장한 내용
        assertThat(detail.get("safetyRating").isNull()).isTrue(); // 항목 평가는 저장하지 않았다
        assertThat(detail.get("authorNickname").asString()).isEqualTo("천안야간런");
        assertThat(row(admin(mvc.get().uri("/api/v1/admin/review-reports?status=DELETED&size=100")), review)
                .get("reviewDeleted").asBoolean()).isTrue();
        // 이미 지운 리뷰
        assertError(handle(review, "DELETED", null), HttpStatus.NOT_FOUND, "REVIEW-003");
    }

    @Test
    void reviewWithoutReportsCanBeDeleted() {
        assertThat(handle(review, "DELETED", null)).hasStatusOk();

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM review.reviews WHERE id = ?", Long.class, review)).isZero();
        // 신고 기록도 없으니 상세는 찾을 수 없다
        assertError(admin(mvc.get().uri("/api/v1/admin/reviews/{id}", review)), HttpStatus.NOT_FOUND, "REVIEW-003");
    }

    @Test
    void rejectsInvalidRequest() {
        assertError(handle(review, "PENDING", null), HttpStatus.BAD_REQUEST, "COMMON-001");
        assertError(handle(review, "DISMISSED", "가".repeat(201)), HttpStatus.BAD_REQUEST, "COMMON-001");
        assertError(admin(mvc.get().uri("/api/v1/admin/reviews?size=101")), HttpStatus.BAD_REQUEST, "COMMON-001");
        assertError(admin(mvc.get().uri("/api/v1/admin/reviews?rating=6")), HttpStatus.BAD_REQUEST, "COMMON-001");
        assertError(admin(mvc.get().uri("/api/v1/admin/review-reports?status=SPAM")), HttpStatus.BAD_REQUEST, "COMMON-001");
    }

    /** 근거 기록 없이 리뷰 1건. */
    private UUID review(UUID member, int rating) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO review.reviews (id, course_id, member_id, source_run_record_id, rating, safety_rating,
                    road_rating, lighting_rating, amenity_rating, content, tags, best_progress_percent, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 1, 1, 1, 1, '광고) 러닝화 최저가', '{}', 100, now(), now())""",
                id, course, member, UUID.randomUUID(), rating);
        return id;
    }

    /** 다른 회원이 앱에서 신고한다(G2-2). */
    private void report(UUID reviewId, String reason) {
        assertThat(mvc.post().uri("/api/v1/reviews/{reviewId}/reports", reviewId)
                .with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString())))
                .contentType(MediaType.APPLICATION_JSON)
                .content(jsonMapper.writeValueAsString(Map.of("reason", reason)))
                .exchange()).hasStatusOk();
    }

    private MvcTestResult handle(UUID reviewId, String result, String memo) {
        Map<String, String> body = new HashMap<>();
        body.put("result", result);
        body.put("memo", memo);
        return admin(mvc.post().uri("/api/v1/admin/reviews/{id}/handle", reviewId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(jsonMapper.writeValueAsString(body)));
    }

    private MvcTestResult admin(MockMvcTester.MockMvcRequestBuilder request) {
        return request.with(httpBasic("test-admin", "test-admin-password")).exchange();
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    /** 목록 응답에서 이 리뷰 줄. 없으면 {@code null} */
    private JsonNode row(MvcTestResult result, UUID reviewId) throws Exception {
        List<JsonNode> rows = data(result).get("content").valueStream().toList();
        return rows.stream().filter(r -> r.get("reviewId").asString().equals(reviewId.toString())).findFirst().orElse(null);
    }

    private static void assertError(MvcTestResult result, HttpStatus status, String code) {
        assertThat(result).hasStatus(status).bodyJson().extractingPath("$.code").isEqualTo(code);
    }
}
