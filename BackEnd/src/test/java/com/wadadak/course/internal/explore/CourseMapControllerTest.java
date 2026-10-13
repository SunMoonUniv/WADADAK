package com.wadadak.course.internal.explore;

import com.wadadak.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 다른 테스트의 코스(서울)와 겹치지 않게 제주에서, 테스트마다 다른 지도 범위를 쓴다. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseMapControllerTest {

    private static final Instant NOW = Instant.parse("2026-10-01T00:00:00Z");

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    @Test
    void returnsActiveCoursesStartingInsideTheArea() throws Exception {
        UUID inside = insert(33.405, 126.305);
        // 출발점은 범위 밖(남쪽)이고 경로만 범위 안을 지난다
        insert(33.395, 126.305);
        UUID hidden = insert(33.406, 126.306);
        jdbcTemplate.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'EXPIRED', hidden_at = now() WHERE id = ?",
                hidden);

        MvcTestResult result = find("swLat=33.400&swLng=126.300&neLat=33.410&neLng=126.310");

        assertThat(result).hasStatusOk();
        JsonNode data = data(result);
        assertThat(data.get("totalCount").asInt()).isEqualTo(1);
        JsonNode course = data.get("courses").get(0);
        assertThat(course.get("courseId").asString()).isEqualTo(inside.toString());
        assertThat(course.get("name").asString()).isEqualTo("지도 코스 " + inside);
        // 첫 점이 출발점(코스 방향)
        assertThat(course.get("route").get(0).get("lat").asDouble()).isEqualTo(33.405);
        assertThat(course.get("route").get(1).get("lat").asDouble()).isCloseTo(33.415, within(1e-9));
    }

    @Test
    void filtersByDistanceDifficultyTagsAndType() throws Exception {
        UUID shortEasy = insert(33.421, 126.301, 2_999, "EASY", "{FLAT}", "CUSTOM", NOW);
        UUID minMedium = insert(33.422, 126.302, 3_000, "MEDIUM", "{FLAT,SHADE}", "CUSTOM", NOW);
        UUID maxHardGps = insert(33.423, 126.303, 5_000, "HARD", "{FLAT,SHADE,TRACK}", "GPS", NOW);
        UUID longEasy = insert(33.424, 126.304, 5_001, "EASY", "{}", "CUSTOM", NOW);
        String area = "swLat=33.420&swLng=126.300&neLat=33.430&neLng=126.310";

        assertThat(ids(area)).containsExactlyInAnyOrder(shortEasy, minMedium, maxHardGps, longEasy);
        // 거리 하한·상한을 모두 포함한다(FIL-02)
        assertThat(ids(area + "&minDistanceMeters=3000&maxDistanceMeters=5000")).containsExactlyInAnyOrder(minMedium, maxHardGps);
        // 20km+처럼 상한 없이 하한만
        assertThat(ids(area + "&minDistanceMeters=5000")).containsExactlyInAnyOrder(maxHardGps, longEasy);
        // 난이도는 그중 하나(FIL-03)
        assertThat(ids(area + "&difficulties=EASY&difficulties=HARD")).containsExactlyInAnyOrder(shortEasy, maxHardGps, longEasy);
        // 태그는 모두 가져야 한다(FIL-04)
        assertThat(ids(area + "&tags=FLAT&tags=SHADE")).containsExactlyInAnyOrder(minMedium, maxHardGps);
        assertThat(ids(area + "&courseType=GPS")).containsExactly(maxHardGps);
        // 조건끼리는 모두 만족해야 한다
        assertThat(ids(area + "&difficulties=EASY&minDistanceMeters=3000")).containsExactly(longEasy);
    }

    @Test
    void sendsAtMost100NewestCoursesButCountsAll() throws Exception {
        List<UUID> oldestFirst = new ArrayList<>();
        for (int i = 0; i <= CourseMapRepository.MAX_COURSES; i++) {
            oldestFirst.add(insert(33.445, 126.300 + i * 0.00005, 1_000, "EASY", "{}", "CUSTOM", NOW.plusSeconds(i)));
        }

        JsonNode data = data(find("swLat=33.440&swLng=126.299&neLat=33.450&neLng=126.310"));

        assertThat(data.get("totalCount").asInt()).isEqualTo(101);
        List<UUID> sent = ids(data);
        assertThat(sent).hasSize(100);
        assertThat(sent.getFirst()).isEqualTo(oldestFirst.getLast());
        assertThat(sent).doesNotContain(oldestFirst.getFirst());
    }

    @Test
    void emptyAreaHasNoCourses() throws Exception {
        JsonNode data = data(find("swLat=33.460&swLng=126.300&neLat=33.470&neLng=126.310"));

        assertThat(data.get("totalCount").asInt()).isZero();
        assertThat(data.get("courses").size()).isZero();
    }

    @Test
    void rejectsBadRequests() {
        String area = "swLat=33.4&swLng=126.3&neLat=33.5&neLng=126.4";
        // 남쪽 끝이 북쪽 끝보다 크다
        assertBadRequest(find("swLat=33.5&swLng=126.3&neLat=33.4&neLng=126.4"));
        assertBadRequest(find("swLat=33.4&swLng=126.3&neLat=33.5"));
        assertBadRequest(find("swLat=33.4&swLng=126.3&neLat=91&neLng=126.4"));
        assertBadRequest(find(area + "&minDistanceMeters=5000&maxDistanceMeters=3000"));
        assertBadRequest(find(area + "&minDistanceMeters=-1"));
        assertBadRequest(find(area + "&difficulties=VERY_HARD"));
    }

    @Test
    void needsLogin() {
        assertThat(mvc.get().uri("/api/v1/courses/map?swLat=33.4&swLng=126.3&neLat=33.5&neLng=126.4").exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private MvcTestResult find(String query) {
        return mvc.get().uri("/api/v1/courses/map?" + query).with(jwt()).exchange();
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private List<UUID> ids(String query) throws Exception {
        return ids(data(find(query)));
    }

    private static List<UUID> ids(JsonNode data) {
        List<UUID> ids = new ArrayList<>();
        data.get("courses").forEach(course -> ids.add(UUID.fromString(course.get("courseId").asString())));
        return ids;
    }

    private static void assertBadRequest(MvcTestResult result) {
        assertThat(result).hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    private UUID insert(double lat, double lng) {
        return insert(lat, lng, 1_000, "EASY", "{}", "CUSTOM", NOW);
    }

    /** 출발점에서 북쪽으로 약 1.1km 가는 코스를 바로 넣는다. 거리 값은 필터 확인용이라 실제 경로 길이와 다를 수 있다. */
    private UUID insert(double lat, double lng, int distanceMeters, String difficulty, String tags, String courseType,
                        Instant createdAt) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    expires_at, version, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?::varchar[], ST_GeomFromText(?, 4326), ?, ST_GeogFromText(?),
                                '5011025000', '5011000000', '5000000000', 'ACTIVE', ?, 0, ?, ?)""",
                id, UUID.randomUUID(), courseType, "지도 코스 " + id, "지도코스" + id, difficulty, tags,
                "LINESTRING(%s %s, %s %s)".formatted(lng, lat, lng, lat + 0.01), distanceMeters,
                "SRID=4326;POINT(%s %s)".formatted(lng, lat),
                Timestamp.from(createdAt.plusSeconds(30 * 24 * 3600)), Timestamp.from(createdAt), Timestamp.from(createdAt));
        return id;
    }
}
