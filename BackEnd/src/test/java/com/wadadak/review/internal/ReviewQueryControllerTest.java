package com.wadadak.review.internal;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
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

import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * 리뷰 조회 API(B8·G2·지도 평점·B2/B10 진입). 리뷰와 주행 기록 복사본은 SQL로 직접 넣어 작성 시각·별점을 정해 둔다.
 * 기동 방식은 {@link ReviewControllerTest}와 같다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class ReviewQueryControllerTest {

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    @MockitoBean
    MemberApi memberApi;

    /** 사진 저장소는 흉내만 낸다. 사진 주소만 만들면 된다 */
    @MockitoBean
    ObjectStorage storage;

    private UUID course;
    private UUID me;

    /** {@code @ApplicationModuleTest}는 테스트 인스턴스를 클래스당 하나만 만들어서 ID를 테스트마다 새로 만든다. */
    @BeforeEach
    void setUp() {
        course = UUID.randomUUID();
        me = UUID.randomUUID();
        // 닉네임은 "닉-" + 회원 ID 앞 4글자
        given(memberApi.getProfiles(any())).willAnswer(call -> call.<Set<UUID>>getArgument(0).stream()
                .map(id -> new MemberProfile(id, nickname(id), null, false))
                .toList());
        given(storage.url(anyString())).willAnswer(call -> "https://files.test/wadadak/" + call.getArgument(0));
    }

    @Test
    void summarizesRatingsOfActiveCourse() throws Exception {
        review(UUID.randomUUID(), course, 5, 5, at("2026-10-01T00:00:00Z"));
        review(UUID.randomUUID(), course, 4, 4, at("2026-10-02T00:00:00Z"));
        review(UUID.randomUUID(), course, 4, 3, at("2026-10-03T00:00:00Z"));
        review(UUID.randomUUID(), UUID.randomUUID(), 1, 1, at("2026-10-03T00:00:00Z")); // 다른 코스는 섞이지 않는다

        JsonNode data = data(get("/api/v1/reviews/summary?courseId=" + course));

        assertThat(data.get("reviewCount").asInt()).isEqualTo(3);
        assertThat(data.get("averageRating").asDouble()).isEqualTo(4.3); // 13 / 3 = 4.33
        JsonNode counts = data.get("ratingCounts");
        assertThat(List.of(counts.get("five").asInt(), counts.get("four").asInt(), counts.get("three").asInt(),
                counts.get("two").asInt(), counts.get("one").asInt())).containsExactly(1, 2, 0, 0, 0);
        assertThat(data.get("itemAverages").get("safety").asDouble()).isEqualTo(4.0); // 12 / 3
        assertThat(data.get("itemAverages").get("road").asDouble()).isEqualTo(4.0);
    }

    @Test
    void hiddenCourseShowsNoReviews() throws Exception {
        review(UUID.randomUUID(), course, 5, 5, at("2026-10-01T00:00:00Z"));
        hide(course);

        JsonNode summary = data(get("/api/v1/reviews/summary?courseId=" + course));
        assertThat(summary.get("reviewCount").asInt()).isZero();
        assertThat(summary.get("averageRating").isNull()).isTrue();
        assertThat(summary.get("itemAverages").get("safety").isNull()).isTrue();
        assertThat(data(get("/api/v1/reviews?courseId=" + course)).get("content")).isEmpty();
    }

    @Test
    void sortsAndPagesReviewCards() throws Exception {
        UUID old5 = review(UUID.randomUUID(), course, 5, 5, at("2026-10-01T00:00:00Z"));
        UUID new5 = review(UUID.randomUUID(), course, 5, 5, at("2026-10-03T00:00:00Z"));
        UUID mid3 = review(UUID.randomUUID(), course, 3, 3, at("2026-10-02T00:00:00Z"));
        UUID mid1 = review(UUID.randomUUID(), course, 1, 1, at("2026-10-02T12:00:00Z"));

        assertThat(reviewIds(list("sort=LATEST"))).containsExactly(new5, mid1, mid3, old5);
        // 같은 별점이면 최신순
        assertThat(reviewIds(list("sort=HIGHEST"))).containsExactly(new5, old5, mid3, mid1);
        assertThat(reviewIds(list("sort=LOWEST"))).containsExactly(mid1, mid3, new5, old5);

        JsonNode first = list("sort=LATEST&size=3");
        assertThat(reviewIds(first)).containsExactly(new5, mid1, mid3);
        String cursor = first.get("nextCursor").asString();
        JsonNode second = list("sort=LATEST&size=3&cursor=" + cursor);
        assertThat(reviewIds(second)).containsExactly(old5);
        assertThat(second.get("nextCursor").isNull()).isTrue();

        assertError(get("/api/v1/reviews?courseId=" + course + "&sort=POPULAR"), HttpStatus.BAD_REQUEST, "COMMON-001");
    }

    @Test
    void cardShowsAuthorAndCompletedCount() throws Exception {
        UUID writer = UUID.randomUUID();
        runRecord(writer, course, true, true, 100, at("2026-10-01T00:00:00Z"));
        runRecord(writer, course, false, true, 100, at("2026-10-02T00:00:00Z")); // 자격 없어도 완주면 센다
        runRecord(writer, course, true, false, 62, at("2026-10-03T00:00:00Z"));  // 미완주는 세지 않는다
        UUID deleted = runRecord(writer, course, true, true, 100, at("2026-10-04T00:00:00Z"));
        jdbcTemplate.update("UPDATE review.course_run_records SET deleted = TRUE WHERE run_record_id = ?", deleted);
        review(writer, course, 4, 5, at("2026-10-05T00:00:00Z"));
        review(me, course, 3, 3, at("2026-10-01T00:00:00Z"));

        JsonNode cards = list("").get("content");

        JsonNode card = cards.get(0);
        assertThat(card.get("memberId").asString()).isEqualTo(writer.toString());
        assertThat(card.get("nickname").asString()).isEqualTo(nickname(writer));
        assertThat(card.get("mine").asBoolean()).isFalse();
        assertThat(card.get("completedCount").asInt()).isEqualTo(2);
        assertThat(card.get("tags").get(0).asString()).isEqualTo("NIGHT_VIEW");
        assertThat(cards.get(1).get("mine").asBoolean()).isTrue();
        assertThat(cards.get(1).get("completedCount").asInt()).isZero();
    }

    @Test
    void filtersPhotoOnlyAndExcludesMine() throws Exception {
        UUID withPhoto = review(UUID.randomUUID(), course, 5, 5, at("2026-10-01T00:00:00Z"));
        String second = photo(withPhoto, 1);
        String first = photo(withPhoto, 0);
        UUID others = review(UUID.randomUUID(), course, 4, 4, at("2026-10-02T00:00:00Z"));
        review(me, course, 3, 3, at("2026-10-03T00:00:00Z"));

        JsonNode photoOnly = list("photoOnly=true");
        assertThat(reviewIds(photoOnly)).containsExactly(withPhoto);
        // 넣은 순서가 아니라 보이는 순서(display_order)대로
        JsonNode photos = photoOnly.get("content").get(0).get("photos");
        assertThat(photos.get(0).get("key").asString()).isEqualTo(first);
        assertThat(photos.get(0).get("url").asString()).isEqualTo("https://files.test/wadadak/" + first);
        assertThat(photos.get(1).get("key").asString()).isEqualTo(second);

        JsonNode othersOnly = list("excludeMine=true");
        assertThat(reviewIds(othersOnly)).containsExactly(others, withPhoto);
        assertThat(othersOnly.get("content").get(0).get("photos")).isEmpty();
    }

    @Test
    void listStillWorksWhenProfilesFail() throws Exception {
        review(UUID.randomUUID(), course, 5, 5, at("2026-10-01T00:00:00Z"));
        willThrow(new IllegalStateException("member 장애")).given(memberApi).getProfiles(any());

        JsonNode card = list("").get("content").get(0);

        assertThat(card.get("nickname").isNull()).isTrue();
        assertThat(card.get("rating").asInt()).isEqualTo(5);
    }

    @Test
    void myReviewBeforeWritingGivesLatestEligibleRecord() throws Exception {
        runRecord(me, course, true, true, 100, at("2026-10-01T00:00:00Z"));
        UUID latest = runRecord(me, course, true, false, 40, at("2026-10-03T00:00:00Z"));
        runRecord(me, course, false, true, 100, at("2026-10-04T00:00:00Z")); // 더 최근이지만 자격 없음
        UUID deleted = runRecord(me, course, true, true, 100, at("2026-10-05T00:00:00Z"));
        jdbcTemplate.update("UPDATE review.course_run_records SET deleted = TRUE WHERE run_record_id = ?", deleted);

        JsonNode data = data(get("/api/v1/reviews/me?courseId=" + course));

        assertThat(data.get("review").isNull()).isTrue();
        assertThat(data.get("sourceRecordDeleted").asBoolean()).isFalse();
        JsonNode record = data.get("eligibleRecord");
        assertThat(record.get("runRecordId").asString()).isEqualTo(latest.toString());
        assertThat(record.get("progressPercent").asInt()).isEqualTo(40);
        assertThat(record.get("completed").asBoolean()).isFalse();
        assertThat(record.get("courseDistanceMeters").asInt()).isEqualTo(5200);
        assertThat(record.get("endedAt").asString()).isEqualTo("2026-10-03T00:00:00Z");
    }

    @Test
    void myReviewTellsSourceRecordDeleted() throws Exception {
        UUID source = runRecord(me, course, true, true, 100, at("2026-10-01T00:00:00Z"));
        UUID reviewId = review(me, course, 4, 4, source, at("2026-10-02T00:00:00Z"));
        jdbcTemplate.update("UPDATE review.course_run_records SET deleted = TRUE WHERE run_record_id = ?", source);

        JsonNode data = data(get("/api/v1/reviews/me?courseId=" + course));

        assertThat(data.get("review").get("reviewId").asString()).isEqualTo(reviewId.toString());
        assertThat(data.get("review").get("mine").asBoolean()).isTrue();
        assertThat(data.get("review").get("safetyRating").asInt()).isEqualTo(4);
        assertThat(data.get("review").get("photos")).isEmpty();
        assertThat(data.get("sourceRecordDeleted").asBoolean()).isTrue();
        assertThat(data.get("eligibleRecord").isNull()).isTrue(); // 남은 자격 기록이 없다
    }

    @Test
    void myReviewOnHiddenCourseHasNoEligibleRecord() throws Exception {
        UUID source = runRecord(me, course, true, true, 100, at("2026-10-01T00:00:00Z"));
        review(me, course, 4, 4, source, at("2026-10-02T00:00:00Z"));
        hide(course);

        JsonNode data = data(get("/api/v1/reviews/me?courseId=" + course));

        assertThat(data.get("review").isNull()).isFalse(); // 지울 수 있게 내 리뷰는 보인다
        assertThat(data.get("eligibleRecord").isNull()).isTrue();
    }

    @Test
    void ratingsForManyCoursesInRequestOrder() throws Exception {
        UUID rated = UUID.randomUUID();
        UUID noReview = UUID.randomUUID();
        UUID hidden = UUID.randomUUID();
        review(UUID.randomUUID(), rated, 5, 5, at("2026-10-01T00:00:00Z"));
        review(UUID.randomUUID(), rated, 4, 4, at("2026-10-02T00:00:00Z"));
        review(UUID.randomUUID(), hidden, 5, 5, at("2026-10-01T00:00:00Z"));
        hide(hidden);

        JsonNode data = data(get("/api/v1/reviews/ratings?courseIds=" + noReview + "," + rated + "," + hidden));

        assertThat(data).hasSize(3);
        assertThat(data.get(0).get("courseId").asString()).isEqualTo(noReview.toString());
        assertThat(data.get(0).get("averageRating").isNull()).isTrue();
        assertThat(data.get(1).get("averageRating").asDouble()).isEqualTo(4.5);
        assertThat(data.get(2).get("averageRating").isNull()).isTrue();
    }

    @Test
    void ratingsRejectsMoreThan100Courses() {
        String ids = IntStream.range(0, ReviewQueryService.MAX_COURSE_IDS + 1)
                .mapToObj(i -> UUID.randomUUID().toString())
                .collect(Collectors.joining(","));

        assertError(get("/api/v1/reviews/ratings?courseIds=" + ids), HttpStatus.BAD_REQUEST, "COMMON-001");
    }

    /** 근거 기록 없이 리뷰 1건. 항목 평가 4개는 모두 {@code items}, 태그는 야경 좋음 하나다. */
    private UUID review(UUID member, UUID courseId, int rating, int items, Instant createdAt) {
        return review(member, courseId, rating, items, UUID.randomUUID(), createdAt);
    }

    private UUID review(UUID member, UUID courseId, int rating, int items, UUID source, Instant createdAt) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO review.reviews (id, course_id, member_id, source_run_record_id, rating, safety_rating,
                            road_rating, lighting_rating, amenity_rating, content, tags, best_progress_percent, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '후기', '{NIGHT_VIEW}', 100, ?, ?)""",
                id, courseId, member, source, rating, items, items, items, items,
                Timestamp.from(createdAt), Timestamp.from(createdAt));
        return id;
    }

    private UUID runRecord(UUID member, UUID courseId, boolean eligible, boolean completed, int progressPercent, Instant endedAt) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO review.course_run_records (run_record_id, course_id, member_id, review_eligible, completed,
                            progress_percent, course_distance_meters, course_elapsed_seconds, ended_at, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, 5200, 1634, ?, now(), now())""",
                id, courseId, member, eligible, completed, progressPercent, Timestamp.from(endedAt));
        return id;
    }

    /** 리뷰 사진 1장. 사진 키는 리뷰 하나만 쓸 수 있어서(유니크) 매번 새로 만든다. */
    private String photo(UUID reviewId, int order) {
        String key = "review/" + UUID.randomUUID() + ".jpg";
        jdbcTemplate.update("""
                INSERT INTO review.review_photos (id, review_id, photo_key, display_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, now(), now())""", UUID.randomUUID(), reviewId, key, order);
        return key;
    }

    private void hide(UUID courseId) {
        jdbcTemplate.update("""
                INSERT INTO review.course_status_copies (course_id, status, source_version, created_at, updated_at)
                VALUES (?, 'HIDDEN', 1, now(), now())""", courseId);
    }

    private JsonNode list(String query) throws Exception {
        return data(get("/api/v1/reviews?courseId=" + course + "&" + query));
    }

    private MvcTestResult get(String uri) {
        return mvc.get().uri(uri).with(jwt().jwt(j -> j.subject(me.toString()))).exchange();
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private static List<UUID> reviewIds(JsonNode slice) {
        List<UUID> ids = new ArrayList<>();
        slice.get("content").forEach(card -> ids.add(UUID.fromString(card.get("reviewId").asString())));
        return ids;
    }

    private static String nickname(UUID memberId) {
        return "닉-" + memberId.toString().substring(0, 4);
    }

    private static Instant at(String instant) {
        return Instant.parse(instant);
    }

    private static void assertError(MvcTestResult result, HttpStatus status, String code) {
        assertThat(result).hasStatus(status).bodyJson().extractingPath("$.code").isEqualTo(code);
    }
}
