package com.wadadak.review.internal;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.event.review.ReviewCreatedEvent;
import com.wadadak.event.review.ReviewDeletedEvent;
import com.wadadak.event.review.ReviewUpdatedEvent;
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
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * review 단독 기동. run 이벤트 처리가 아직 없어서 주행 기록 복사본은 테스트가 직접 넣는다.
 *
 * <p>[읽는 법]
 * <ul>
 *   <li>{@code @ApplicationModuleTest}: review 모듈만 띄운다. 다른 도메인 모듈 없이 뜨는지가 곧 "따로 떼어낼 수 있다"는 증거다(개발 정책 10.6)</li>
 *   <li>{@code @Import(TestcontainersConfiguration.class)}: Docker로 테스트용 PostgreSQL을 띄운다. 그래서 Docker가 켜져 있어야 한다</li>
 *   <li>{@code MockMvcTester}: 서버를 실제로 띄우지 않고 HTTP 요청을 흉내 내 컨트롤러를 부른다</li>
 *   <li>{@code jwt().jwt(j -> j.subject(...))}: 그 회원으로 로그인한 요청처럼 만든다(토큰의 sub = 회원 ID)</li>
 *   <li>{@code AssertablePublishedEvents}: 테스트 중 발행된 이벤트를 모아 두어, 리뷰 이벤트가 맞게 나갔는지 확인한다</li>
 * </ul>
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class ReviewControllerTest {

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    @Test
    void writesReviewWithBestProgress(AssertablePublishedEvents events) throws Exception {
        UUID member = UUID.randomUUID();
        UUID course = UUID.randomUUID();
        UUID eligible = runRecord(member, course, true, false, 62);
        runRecord(member, course, false, true, 100); // 완주했지만 자격 없는 기록도 최고 진행도에는 들어간다

        MvcTestResult result = write(member, course, eligible, 4, "  야경이 좋아요  ", "[\"NIGHT_VIEW\", \"FEW_SIGNALS\"]");

        assertThat(result).hasStatusOk();
        JsonNode data = data(result);
        assertThat(data.get("rating").asInt()).isEqualTo(4);
        assertThat(data.get("content").asString()).isEqualTo("야경이 좋아요");
        assertThat(data.get("bestProgressPercent").asInt()).isEqualTo(100);
        assertThat(data.get("tags")).hasSize(2);
        UUID reviewId = UUID.fromString(data.get("reviewId").asString());
        Instant createdAt = jdbcTemplate.queryForObject("SELECT created_at FROM review.reviews WHERE id = ?", Timestamp.class, reviewId)
                .toInstant();
        assertThat(events).contains(ReviewCreatedEvent.class)
                .matching(e -> e.reviewId().equals(reviewId) && e.courseId().equals(course) && e.rating() == 4
                        && e.createdAt().equals(createdAt));
    }

    @Test
    void requiresEligibleRecordOfMine() {
        UUID member = UUID.randomUUID();
        UUID course = UUID.randomUUID();
        UUID notEligible = runRecord(member, course, false, true, 100);
        UUID deleted = runRecord(member, course, true, true, 100);
        jdbcTemplate.update("UPDATE review.course_run_records SET deleted = true WHERE run_record_id = ?", deleted);
        UUID othersRecord = runRecord(UUID.randomUUID(), course, true, true, 100);
        UUID otherCourse = runRecord(member, UUID.randomUUID(), true, true, 100);

        for (UUID source : new UUID[]{notEligible, deleted, othersRecord, otherCourse, UUID.randomUUID()}) {
            assertError(write(member, course, source, 5, null, null), HttpStatus.FORBIDDEN, "REVIEW-001");
        }
    }

    @Test
    void oneReviewPerCourse() {
        UUID member = UUID.randomUUID();
        UUID course = UUID.randomUUID();
        UUID record = runRecord(member, course, true, true, 100);
        assertThat(write(member, course, record, 5, null, null)).hasStatusOk();

        assertError(write(member, course, record, 3, null, null), HttpStatus.CONFLICT, "REVIEW-002");
    }

    @Test
    void cannotWriteOnHiddenOrDeletedCourse() {
        UUID member = UUID.randomUUID();
        UUID course = UUID.randomUUID();
        UUID record = runRecord(member, course, true, true, 100);
        jdbcTemplate.update("""
                INSERT INTO review.course_status_copies (course_id, status, source_version, created_at, updated_at)
                VALUES (?, 'HIDDEN', 1, now(), now())""", course);

        assertError(write(member, course, record, 5, null, null), HttpStatus.CONFLICT, "REVIEW-005");
    }

    @Test
    void editsOwnReviewEvenAfterSourceRecordDeleted(AssertablePublishedEvents events) throws Exception {
        UUID member = UUID.randomUUID();
        UUID course = UUID.randomUUID();
        UUID record = runRecord(member, course, true, false, 40);
        JsonNode written = data(write(member, course, record, 5, "처음 후기", "[\"CROWDED\"]"));
        UUID reviewId = UUID.fromString(written.get("reviewId").asString());
        jdbcTemplate.update("UPDATE review.course_run_records SET deleted = true WHERE run_record_id = ?", record);

        MvcTestResult result = edit(member, reviewId, 3, "   ", "[\"GOOD_SURFACE\"]");

        assertThat(result).hasStatusOk();
        JsonNode data = data(result);
        assertThat(data.get("rating").asInt()).isEqualTo(3);
        assertThat(data.get("content").isNull()).isTrue();
        assertThat(data.get("tags").get(0).asString()).isEqualTo("GOOD_SURFACE");
        // 근거 기록이 지워져도 저장된 최고 진행도는 줄지 않는다(정책 공통 5)
        assertThat(data.get("bestProgressPercent").asInt()).isEqualTo(40);
        assertThat(data.get("createdAt").asString()).isEqualTo(written.get("createdAt").asString());
        assertThat(events).contains(ReviewUpdatedEvent.class)
                .matching(e -> e.reviewId().equals(reviewId) && e.oldRating() == 5 && e.newRating() == 3
                        && e.createdAt().toString().equals(written.get("createdAt").asString()));
    }

    @Test
    void editWithSameRatingStillPublishesEvent(AssertablePublishedEvents events) throws Exception {
        UUID member = UUID.randomUUID();
        UUID course = UUID.randomUUID();
        UUID reviewId = UUID.fromString(data(write(member, course, runRecord(member, course, true, true, 100), 4, null, null))
                .get("reviewId").asString());

        assertThat(edit(member, reviewId, 4, "내용만 고침", null)).hasStatusOk();

        assertThat(events).contains(ReviewUpdatedEvent.class)
                .matching(e -> e.reviewId().equals(reviewId) && e.oldRating() == 4 && e.newRating() == 4);
    }

    @Test
    void onlyWriterCanEditOrDelete() throws Exception {
        UUID member = UUID.randomUUID();
        UUID course = UUID.randomUUID();
        UUID reviewId = UUID.fromString(data(write(member, course, runRecord(member, course, true, true, 100), 5, null, null))
                .get("reviewId").asString());
        UUID stranger = UUID.randomUUID();

        assertError(edit(stranger, reviewId, 1, null, null), HttpStatus.FORBIDDEN, "REVIEW-004");
        assertError(delete(stranger, reviewId), HttpStatus.FORBIDDEN, "REVIEW-004");
        assertError(delete(member, UUID.randomUUID()), HttpStatus.NOT_FOUND, "REVIEW-003");
    }

    @Test
    void deletesReviewAndAllowsWritingAgain(AssertablePublishedEvents events) throws Exception {
        UUID member = UUID.randomUUID();
        UUID course = UUID.randomUUID();
        UUID record = runRecord(member, course, true, true, 100);
        UUID reviewId = UUID.fromString(data(write(member, course, record, 2, null, null)).get("reviewId").asString());

        assertThat(delete(member, reviewId)).hasStatusOk();

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM review.reviews WHERE id = ?", Integer.class, reviewId)).isZero();
        assertThat(events).contains(ReviewDeletedEvent.class)
                .matching(e -> e.reviewId().equals(reviewId) && e.courseId().equals(course) && e.rating() == 2);
        assertThat(write(member, course, record, 4, null, null)).hasStatusOk();
    }

    @Test
    void rejectsInvalidInput() {
        UUID member = UUID.randomUUID();
        UUID course = UUID.randomUUID();
        UUID record = runRecord(member, course, true, true, 100);

        assertError(write(member, course, record, 6, null, null), HttpStatus.BAD_REQUEST, "COMMON-001");
        assertError(write(member, course, record, 0, null, null), HttpStatus.BAD_REQUEST, "COMMON-001");
        assertError(write(member, course, record, 5, "가".repeat(201), null), HttpStatus.BAD_REQUEST, "COMMON-001");
        assertError(write(member, course, record, 5, null, "[\"SUNNY\"]"), HttpStatus.BAD_REQUEST, "COMMON-001");
        assertThat(write(member, course, record, 5, "가".repeat(200), null)).hasStatusOk();
    }

    /** 리뷰 자격·완주·진행도를 정한 코스 주행 기록 복사본 1건. run 이벤트 처리가 생기기 전까지 테스트가 직접 넣는다. */
    private UUID runRecord(UUID member, UUID course, boolean eligible, boolean completed, int progressPercent) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO review.course_run_records (run_record_id, course_id, member_id, review_eligible, completed,
                    progress_percent, course_distance_meters, course_elapsed_seconds, ended_at, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, 5200, 1634, now(), now(), now())""", id, course, member, eligible, completed, progressPercent);
        return id;
    }

    private MvcTestResult write(UUID member, UUID course, UUID source, int rating, String content, String tagsJson) {
        String body = """
                {"courseId": "%s", "sourceRunRecordId": "%s", %s}""".formatted(course, source, contentJson(rating, content, tagsJson));
        return mvc.post().uri("/api/v1/reviews").with(jwt().jwt(j -> j.subject(member.toString())))
                .contentType(MediaType.APPLICATION_JSON).content(body).exchange();
    }

    private MvcTestResult edit(UUID member, UUID reviewId, int rating, String content, String tagsJson) {
        return mvc.put().uri("/api/v1/reviews/{id}", reviewId).with(jwt().jwt(j -> j.subject(member.toString())))
                .contentType(MediaType.APPLICATION_JSON).content("{" + contentJson(rating, content, tagsJson) + "}").exchange();
    }

    private MvcTestResult delete(UUID member, UUID reviewId) {
        return mvc.delete().uri("/api/v1/reviews/{id}", reviewId).with(jwt().jwt(j -> j.subject(member.toString()))).exchange();
    }

    private String contentJson(int rating, String content, String tagsJson) {
        return """
                "rating": %d, "safetyRating": 5, "roadRating": 4, "lightingRating": 5, "amenityRating": 3,
                "content": %s, "tags": %s""".formatted(rating, content == null ? "null" : jsonMapper.writeValueAsString(content),
                tagsJson == null ? "null" : tagsJson);
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private static void assertError(MvcTestResult result, HttpStatus status, String code) {
        assertThat(result).hasStatus(status).bodyJson().extractingPath("$.code").isEqualTo(code);
    }
}
