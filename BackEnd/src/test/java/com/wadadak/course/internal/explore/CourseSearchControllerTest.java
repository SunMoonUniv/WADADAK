package com.wadadak.course.internal.explore;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.course.internal.course.CourseName;
import com.wadadak.member.MemberApi;
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
import java.util.Locale;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 검색은 지도 범위와 상관없이 이름으로 찾는다. 다른 테스트의 코스와 섞이지 않게 테스트마다 다른 말을 이름에 넣는다. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseSearchControllerTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    private static final Instant NOW = Instant.parse("2026-10-01T00:00:00Z");

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    @Test
    void findsActiveCoursesWhoseNameContainsTheQueryIgnoringSpacesAndCase() throws Exception {
        String word = word();
        UUID older = insert("Night " + word + " Run", 37.50, 127.00, NOW);
        // 지도 범위와 상관없이 전국에서 찾는다
        UUID newer = insert("한강 NIGHT" + word + " 야경", 35.10, 129.00, NOW.plusSeconds(1));
        insert("Day " + word, 37.51, 127.01, NOW.plusSeconds(2));
        UUID hidden = insert("Night " + word + " Old", 37.52, 127.02, NOW.plusSeconds(3));
        jdbcTemplate.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'EXPIRED', hidden_at = now() WHERE id = ?",
                hidden);
        String query = "night " + word.toUpperCase(Locale.ROOT);

        // 공백과 대소문자는 보지 않는다. 수는 쪽마다 같다
        JsonNode first = data(search(query, "sort=LATEST&size=1"));
        assertThat(first.get("totalCount").asInt()).isEqualTo(2);
        assertThat(ids(first)).containsExactly(newer);
        JsonNode second = data(search(query, "sort=LATEST&size=1&cursor=" + first.get("nextCursor").asString()));
        assertThat(second.get("totalCount").asInt()).isEqualTo(2);
        assertThat(ids(second)).containsExactly(older);
        assertThat(second.get("nextCursor").isNull()).isTrue();

        // 이름 가운데 일부도 찾는다. 카드는 코스 목록과 같다
        JsonNode middle = data(search(word + "야 경", "sort=LATEST"));
        assertThat(ids(middle)).containsExactly(newer);
        JsonNode card = middle.get("content").get(0);
        assertThat(card.get("name").asString()).isEqualTo("한강 NIGHT" + word + " 야경");
        assertThat(card.get("route").get(0).get("lat").asDouble()).isEqualTo(35.10);

        JsonNode none = data(search("없는" + word, "sort=LATEST"));
        assertThat(none.get("totalCount").asInt()).isZero();
        assertThat(none.get("content").isEmpty()).isTrue();
        assertThat(none.get("nextCursor").isNull()).isTrue();
    }

    @Test
    void sortsLikeTheCourseList() throws Exception {
        String word = word();
        UUID far = insert("Loop " + word + " A", 37.60, 127.00, NOW);
        UUID near = insert("Loop " + word + " B", 37.50, 127.00, NOW.plusSeconds(1));
        UUID noReviews = insert("Loop " + word + " C", 37.55, 127.00, NOW.plusSeconds(2));
        reviews(far, 5, 1);
        reviews(near, 8, 2);

        assertThat(ids(data(search("loop" + word, "sort=NEAREST&lat=37.50&lng=127.00")))).containsExactly(near, noReviews, far);

        JsonNode rating = data(search("loop" + word, "sort=RATING"));
        assertThat(ids(rating)).containsExactly(far, near, noReviews);
        assertThat(rating.get("content").get(0).get("averageRating").asDouble()).isEqualTo(5.0);
        assertThat(rating.get("content").get(1).get("reviewCount").asInt()).isEqualTo(2);
        assertThat(rating.get("content").get(2).get("averageRating").isNull()).isTrue();
    }

    @Test
    void rejectsBadSearches() {
        assertBadRequest(mvc.get().uri("/api/v1/courses/search?sort=LATEST").with(jwt()).exchange());
        assertBadRequest(search("a", "sort=LATEST"));
        assertBadRequest(search(" a ", "sort=LATEST"));
        assertBadRequest(search("가".repeat(101), "sort=LATEST"));
        assertBadRequest(search("한강", ""));
        assertBadRequest(search("한강", "sort=NEAREST"));
        assertBadRequest(search("한강", "sort=LATEST&cursor=garbage"));
        // 공백을 빼고 2글자
        assertThat(search("a b", "sort=LATEST")).hasStatusOk();
    }

    @Test
    void countsMatchingCoursesByStartRegionWithTheirBounds() throws Exception {
        String word = word();
        // 영등포구 둘, 서울 중구 · 수원시 장안구 · 서울 강서구 하나씩. 이름에 검색어가 없거나 숨긴 코스는 세지 않는다
        insertIn("1156000000", "한강 " + word + " 야경", 37.52, 126.93);
        insertIn("1156000000", word + " 여의도", 37.53, 126.90);
        insertIn("1114000000", "청계 " + word, 37.56, 126.99);
        insertIn("4111100000", "장안 " + word, 37.30, 127.01);
        insertIn("1150000000", "마곡 " + word, 37.56, 126.83);
        insertIn("1156000000", "다른 말 코스", 37.52, 126.91);
        UUID hidden = insertIn("1121500000", "광진 " + word, 37.54, 127.08);
        jdbcTemplate.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'EXPIRED', hidden_at = now() WHERE id = ?",
                hidden);

        // 코스가 많은 지역부터, 같으면 지역 코드순. 전국에 같은 이름이 있는 중구 · 강서구는 시·도를 붙인다
        JsonNode data = data(regions(word.toUpperCase(Locale.ROOT)));
        assertThat(regionCounts(data))
                .containsExactly("영등포구 2", "서울특별시 중구 1", "서울특별시 강서구 1", "수원시 장안구 1");
        JsonNode yeongdeungpo = data.get("regions").get(0);
        assertThat(yeongdeungpo.get("code").asString()).isEqualTo("1156000000");
        // 걸린 코스 출발점의 범위
        assertThat(yeongdeungpo.get("southWest").get("lat").asDouble()).isEqualTo(37.52);
        assertThat(yeongdeungpo.get("southWest").get("lng").asDouble()).isEqualTo(126.90);
        assertThat(yeongdeungpo.get("northEast").get("lat").asDouble()).isEqualTo(37.53);
        assertThat(yeongdeungpo.get("northEast").get("lng").asDouble()).isEqualTo(126.93);

        assertThat(data(regions("없는" + word)).get("regions").isEmpty()).isTrue();
    }

    @Test
    void rejectsBadRegionSearches() {
        assertBadRequest(mvc.get().uri("/api/v1/courses/search/regions").with(jwt()).exchange());
        assertBadRequest(regions(" a "));
        assertBadRequest(regions("가".repeat(101)));
    }

    @Test
    void needsLogin() {
        assertThat(mvc.get().uri("/api/v1/courses/search?sort=LATEST").param("query", "한강").exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED);
        assertThat(mvc.get().uri("/api/v1/courses/search/regions").param("query", "한강").exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private MvcTestResult search(String query, String rest) {
        return mvc.get().uri("/api/v1/courses/search?" + rest).param("query", query).with(jwt()).exchange();
    }

    private MvcTestResult regions(String query) {
        return mvc.get().uri("/api/v1/courses/search/regions").param("query", query).with(jwt()).exchange();
    }

    /** "이름 개수" 목록. */
    private static List<String> regionCounts(JsonNode data) {
        List<String> counts = new ArrayList<>();
        data.get("regions").forEach(region -> counts.add(region.get("name").asString() + " " + region.get("count").asInt()));
        return counts;
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private static List<UUID> ids(JsonNode data) {
        List<UUID> ids = new ArrayList<>();
        data.get("content").forEach(course -> ids.add(UUID.fromString(course.get("courseId").asString())));
        return ids;
    }

    private static void assertBadRequest(MvcTestResult result) {
        assertThat(result).hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    /** 이 테스트에서만 쓰는 말. 영문 소문자와 숫자 8글자 */
    private static String word() {
        return UUID.randomUUID().toString().replace("-", "").substring(0, 8);
    }

    /** 코스 통계에 리뷰 평점 합과 수를 바로 넣는다 */
    private void reviews(UUID course, int ratingSum, int reviewCount) {
        jdbcTemplate.update("INSERT INTO course.course_stats (course_id, rating_sum, review_count, created_at, updated_at) "
                + "VALUES (?, ?, ?, now(), now())", course, ratingSum, reviewCount);
    }

    private UUID insert(String name, double lat, double lng, Instant createdAt) {
        return insert(name, lat, lng, createdAt, "5011000000");
    }

    /** 출발점이 [sigunguCode] 지역이라고 적힌 코스. 좌표와 지역 코드가 맞지 않아도 된다. */
    private UUID insertIn(String sigunguCode, String name, double lat, double lng) {
        return insert(name, lat, lng, NOW, sigunguCode);
    }

    /** 출발점에서 북쪽으로 약 1.1km 가는 코스를 바로 넣는다. 이름 키는 등록과 같게 만든다. 만료는 등록 30일 뒤. */
    private UUID insert(String name, double lat, double lng, Instant createdAt, String sigunguCode) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    expires_at, version, created_at, updated_at)
                        VALUES (?, ?, 'CUSTOM', ?, ?, 'EASY', '{}', ST_GeomFromText(?, 4326), 1000, ST_GeogFromText(?),
                                ?, ?, ?, 'ACTIVE', ?, 0, ?, ?)""",
                id, UUID.randomUUID(), CourseName.display(name), CourseName.key(name),
                "LINESTRING(%s %s, %s %s)".formatted(lng, lat, lng, lat + 0.01),
                "SRID=4326;POINT(%s %s)".formatted(lng, lat),
                sigunguCode.substring(0, 5) + "10100", sigunguCode, sigunguCode.substring(0, 2) + "00000000",
                Timestamp.from(createdAt.plusSeconds(30 * 24 * 3600)), Timestamp.from(createdAt), Timestamp.from(createdAt));
        return id;
    }
}
