package com.wadadak.course.internal.explore;

import com.wadadak.TestcontainersConfiguration;
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
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 지도 테스트(위도 33.40~33.53)와 겹치지 않게 위도 33.60부터, 테스트마다 다른 지도 범위를 쓴다. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseListControllerTest {

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
    void listsActiveCoursesInTheAreaNewestFirstPageByPage() throws Exception {
        UUID oldest = insert(33.601, 126.301, NOW, "MEDIUM", 3_210, "{SHADE,FLAT}", "GPS");
        UUID middle = insert(33.602, 126.302, NOW.plusSeconds(1));
        UUID newest = insert(33.603, 126.303, NOW.plusSeconds(2));
        // 출발점이 범위 밖(남쪽)
        insert(33.599, 126.301, NOW.plusSeconds(3));
        UUID hidden = insert(33.604, 126.304, NOW.plusSeconds(4));
        jdbcTemplate.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'EXPIRED', hidden_at = now() WHERE id = ?",
                hidden);
        String query = "swLat=33.600&swLng=126.300&neLat=33.610&neLng=126.310&sort=LATEST&size=2";

        JsonNode first = data(list(query));
        assertThat(ids(first)).containsExactly(newest, middle);
        assertThat(first.get("nextCursor").isNull()).isFalse();

        // 쪽을 넘기는 사이 새 코스가 등록돼도 이미 받은 코스가 다시 나오지 않는다.
        insert(33.605, 126.305, NOW.plusSeconds(5));
        JsonNode second = data(list(query + "&cursor=" + first.get("nextCursor").asString()));
        assertThat(ids(second)).containsExactly(oldest);
        assertThat(second.get("nextCursor").isNull()).isTrue();

        JsonNode card = second.get("content").get(0);
        assertThat(card.get("name").asString()).isEqualTo("목록 코스 " + oldest);
        assertThat(card.get("distanceMeters").asInt()).isEqualTo(3_210);
        assertThat(card.get("difficulty").asString()).isEqualTo("MEDIUM");
        // FIL-04 순서
        List<String> tags = new ArrayList<>();
        card.get("tags").forEach(tag -> tags.add(tag.asString()));
        assertThat(tags).containsExactly("FLAT", "SHADE");
        assertThat(card.get("courseType").asString()).isEqualTo("GPS");
        assertThat(Instant.parse(card.get("expiresAt").asString())).isEqualTo(NOW.plusSeconds(30 * 24 * 3600));
        // 첫 점이 출발점
        assertThat(card.get("route").get(0).get("lat").asDouble()).isEqualTo(33.601);
        assertThat(card.get("route").get(0).get("lng").asDouble()).isEqualTo(126.301);
    }

    @Test
    void listsNearestFirstFromTheCurrentLocation() throws Exception {
        UUID far = insert(33.629, 126.309, NOW);
        UUID near = insert(33.6252, 126.305, NOW.plusSeconds(1));
        UUID middle = insert(33.627, 126.305, NOW.plusSeconds(2));
        // 같은 곳에서 출발하면 ID순
        UUID sameA = insert(33.628, 126.305, NOW.plusSeconds(3));
        UUID sameB = insert(33.628, 126.305, NOW.plusSeconds(4));
        List<UUID> same = Stream.of(sameA, sameB).sorted(Comparator.comparing(UUID::toString)).toList();
        String query = "swLat=33.620&swLng=126.300&neLat=33.630&neLng=126.310&sort=NEAREST&lat=33.625&lng=126.305&size=3";

        JsonNode first = data(list(query));
        assertThat(ids(first)).containsExactly(near, middle, same.get(0));
        JsonNode second = data(list(query + "&cursor=" + first.get("nextCursor").asString()));
        assertThat(ids(second)).containsExactly(same.get(1), far);
        assertThat(second.get("nextCursor").isNull()).isTrue();
    }

    @Test
    void listsTheSameCoursesAsTheMap() throws Exception {
        UUID hardShort = insert(33.641, 126.301, NOW, "HARD", 3_000, "{}", "CUSTOM");
        insert(33.642, 126.302, NOW, "EASY", 3_000, "{}", "CUSTOM");
        insert(33.643, 126.303, NOW, "HARD", 6_000, "{}", "CUSTOM");
        String area = "swLat=33.640&swLng=126.300&neLat=33.650&neLng=126.310&difficulties=HARD&maxDistanceMeters=5000";

        List<UUID> listed = ids(data(list(area + "&sort=LATEST")));
        assertThat(listed).containsExactly(hardShort);

        // 지도와 같은 조건이다(MAP-07).
        List<UUID> mapped = new ArrayList<>();
        data(mvc.get().uri("/api/v1/courses/map?" + area).with(jwt()).exchange())
                .get("courses").forEach(course -> mapped.add(UUID.fromString(course.get("courseId").asString())));
        assertThat(mapped).isEqualTo(listed);
    }

    @Test
    void rejectsBadListRequests() {
        String area = "swLat=33.6&swLng=126.3&neLat=33.7&neLng=126.4";
        String latestCursor = CourseListCursor.latest(NOW, UUID.randomUUID()).encode();

        assertBadRequest(list(area));
        // 인기순은 코스 통계(F11) 뒤에 붙는다
        assertBadRequest(list(area + "&sort=POPULAR"));
        assertBadRequest(list(area + "&sort=NEAREST"));
        assertBadRequest(list(area + "&sort=NEAREST&lat=33.65"));
        assertBadRequest(list(area + "&sort=NEAREST&lat=91&lng=126.35"));
        assertBadRequest(list(area + "&sort=LATEST&cursor=garbage"));
        assertBadRequest(list(area + "&sort=NEAREST&lat=33.65&lng=126.35&cursor=" + latestCursor));
        assertBadRequest(list(area + "&sort=LATEST&size=51"));
        assertBadRequest(list("swLat=33.7&swLng=126.3&neLat=33.6&neLng=126.4&sort=LATEST"));
        assertThat(list(area + "&sort=LATEST&cursor=" + latestCursor)).hasStatusOk();
    }

    @Test
    void needsLogin() {
        assertThat(mvc.get().uri("/api/v1/courses?swLat=33.6&swLng=126.3&neLat=33.7&neLng=126.4&sort=LATEST").exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private MvcTestResult list(String query) {
        return mvc.get().uri("/api/v1/courses?" + query).with(jwt()).exchange();
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

    private UUID insert(double lat, double lng, Instant createdAt) {
        return insert(lat, lng, createdAt, "EASY", 1_000, "{}", "CUSTOM");
    }

    /** 출발점에서 북쪽으로 약 1.1km 가는 코스를 바로 넣는다. 거리 값은 확인용이라 실제 경로 길이와 다를 수 있다. 만료는 등록 30일 뒤. */
    private UUID insert(double lat, double lng, Instant createdAt, String difficulty, int distanceMeters, String tags,
                        String courseType) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    expires_at, version, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?::varchar[], ST_GeomFromText(?, 4326), ?, ST_GeogFromText(?),
                                '5011010100', '5011000000', '5000000000', 'ACTIVE', ?, 0, ?, ?)""",
                id, UUID.randomUUID(), courseType, "목록 코스 " + id, "목록코스" + id, difficulty, tags,
                "LINESTRING(%s %s, %s %s)".formatted(lng, lat, lng, lat + 0.01), distanceMeters,
                "SRID=4326;POINT(%s %s)".formatted(lng, lat),
                Timestamp.from(createdAt.plusSeconds(30 * 24 * 3600)), Timestamp.from(createdAt), Timestamp.from(createdAt));
        return id;
    }
}
