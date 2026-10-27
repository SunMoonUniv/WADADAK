package com.wadadak.course.internal.registration;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.event.course.CourseCreatedEvent;
import com.wadadak.member.MemberApi;
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
import org.springframework.test.context.bean.override.convention.TestBean;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * GPS 코스 경로 미리보기(D4)와 등록. 경로는 서울 마포 위도 37.556에서 북쪽으로 3m마다 한 점(1초에 한 점쯤)이다.
 * 테스트끼리 유사도에 걸리지 않게 테스트마다 경도를 약 440m씩 띄운다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class GpsRegistrationControllerTest {

    private static final double START_LAT = 37.5560;
    private static final double M_PER_DEG_LAT = Math.PI * GeoPoint.EARTH_RADIUS_M / 180;
    private static final double M_PER_DEG_LNG = M_PER_DEG_LAT * Math.cos(Math.toRadians(START_LAT));

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    /** 2026-10-01 10:00 Asia/Seoul */
    @TestBean
    Clock clock;

    static Clock clock() {
        return Clock.fixed(Instant.parse("2026-10-01T01:00:00Z"), ZoneId.of("Asia/Seoul"));
    }

    @Test
    void previewJoinsSmallGapAndThinsPoints() throws Exception {
        // 600m 달리고 10m 끊긴 뒤 다시 600m. 곧은 길이라 점은 처음과 끝만 남는다
        List<List<double[]>> segments = List.of(north(START_LAT, 126.9000, 600), north(lat(610), 126.9000, 600));

        MvcTestResult result = preview(UUID.randomUUID(), segments);

        assertThat(result).hasStatusOk();
        JsonNode data = data(result);
        assertThat(data.get("route").size()).isEqualTo(2);
        assertThat(data.get("route").get(0).get("lat").asDouble()).isCloseTo(START_LAT, within(1e-7));
        assertThat(data.get("distanceMeters").asInt()).isBetween(1205, 1215);
        assertThat(data.get("distanceMarkers").size()).isEqualTo(1);
    }

    @Test
    void thinnedCurveStaysWithin2mOfTheRun() throws Exception {
        // 반지름 400m 반원(약 1.26km)을 3m마다. 굽은 길은 점이 남되, 줄인 경로가 원래 점에서 2m 넘게 벗어나지 않는다
        List<double[]> arc = new ArrayList<>();
        double centerLng = lng(126.9500, 400);
        for (double angle = Math.PI; angle >= 0; angle -= 3.0 / 400) {
            arc.add(new double[]{START_LAT + 400 * Math.sin(angle) / M_PER_DEG_LAT, centerLng + 400 * Math.cos(angle) / M_PER_DEG_LNG});
        }

        MvcTestResult result = preview(UUID.randomUUID(), List.of(arc));

        assertThat(result).hasStatusOk();
        JsonNode route = data(result).get("route");
        assertThat(route.size()).isBetween(3, arc.size() / 4);
        StringBuilder line = new StringBuilder("SRID=4326;LINESTRING(");
        for (int i = 0; i < route.size(); i++) {
            line.append(i == 0 ? "" : ",").append(route.get(i).get("lng").asDouble()).append(' ').append(route.get(i).get("lat").asDouble());
        }
        StringBuilder original = new StringBuilder("SRID=4326;MULTIPOINT(");
        for (int i = 0; i < arc.size(); i++) {
            original.append(i == 0 ? "" : ",").append(arc.get(i)[1]).append(' ').append(arc.get(i)[0]);
        }
        Double farthest = jdbcTemplate.queryForObject("""
                        SELECT max(ST_Distance(ST_Transform(d.geom, 5179), ST_Transform(ST_GeomFromEWKT(?), 5179)))
                        FROM ST_Dump(ST_GeomFromEWKT(?)) AS d""",
                Double.class, line.append(')').toString(), original.append(')').toString());
        assertThat(farthest).isLessThanOrEqualTo(2.0 + 1e-6);
    }

    @Test
    void previewRejectsGapThatTurnsAway() {
        // 북쪽으로 달리다 끊기고 100m 동쪽에서 다시 북쪽으로: 빈칸 직선(동쪽)과 진행 방향(북쪽)이 90°
        List<List<double[]>> segments = List.of(north(START_LAT, 126.9000, 600), north(lat(600), lng(126.9000, 100), 600));

        assertError(preview(UUID.randomUUID(), segments), HttpStatus.BAD_REQUEST, "COURSE-011");
    }

    @Test
    void previewRejectsShortOrEmptyRoute() {
        assertError(preview(UUID.randomUUID(), List.of(north(START_LAT, 126.9000, 500))), HttpStatus.BAD_REQUEST, "COURSE-004");
        assertError(preview(UUID.randomUUID(), List.of()), HttpStatus.BAD_REQUEST, "COURSE-003");
    }

    @Test
    void previewHasNoDistanceUpperLimit() throws Exception {
        // 직접 만든 코스의 100km 상한을 쓰지 않는다
        List<List<double[]>> segments = List.of(List.of(new double[]{37.0000, 127.5000}, new double[]{37.0000 + 101_000 / M_PER_DEG_LAT, 127.5000}));

        MvcTestResult result = preview(UUID.randomUUID(), segments);

        assertThat(result).hasStatusOk();
        assertThat(data(result).get("distanceMeters").asInt()).isGreaterThan(100_000);
    }

    @Test
    void registersGpsCourseWithItsSource(AssertablePublishedEvents events) throws Exception {
        UUID memberId = UUID.randomUUID();
        UUID recordId = UUID.randomUUID();

        MvcTestResult result = register(memberId, UUID.randomUUID(), body(recordId, "마포 달린 길 코스", gapped(126.9050)));

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.name").isEqualTo("마포 달린 길 코스");
        UUID courseId = UUID.fromString(data(result).get("courseId").asString());
        assertThat(jdbcTemplate.queryForMap("SELECT course_type, status, creator_id, distance_meters, ST_NPoints(route) AS points "
                        + "FROM course.courses WHERE id = ?", courseId))
                .containsEntry("course_type", "GPS")
                .containsEntry("status", "ACTIVE")
                .containsEntry("creator_id", memberId)
                .containsEntry("points", 2);
        var source = jdbcTemplate.queryForMap("SELECT run_record_id, member_id, source_segments_json FROM course.gps_course_sources WHERE course_id = ?",
                courseId);
        assertThat(source).containsEntry("run_record_id", recordId).containsEntry("member_id", memberId);
        // 원본은 점을 줄이지 않고 고도까지 그대로 둔다
        JsonNode stored = jsonMapper.readTree((String) source.get("source_segments_json"));
        assertThat(stored.size()).isEqualTo(2);
        assertThat(stored.get(0).size()).isEqualTo(201);
        assertThat(stored.get(0).get(0).get("altitudeM").asDouble()).isEqualTo(31.5);
        assertThat(events).contains(CourseCreatedEvent.class)
                .matching(e -> e.courseId().equals(courseId) && e.creatorId().equals(memberId) && recordId.equals(e.sourceRunRecordId()));

        MvcTestResult quota = quota(memberId);
        assertThat(quota).bodyJson().extractingPath("$.data.gps.remaining").isEqualTo(2);
        assertThat(quota).bodyJson().extractingPath("$.data.custom.remaining").isEqualTo(1);
        assertThat(quota).bodyJson().extractingPath("$.data.usedRunRecordIds[0]").isEqualTo(recordId.toString());
    }

    @Test
    void runRecordIsUsedOnlyOnceEvenAfterItsCourseIsDeleted() throws Exception {
        UUID memberId = UUID.randomUUID();
        UUID recordId = UUID.randomUUID();
        MvcTestResult first = register(memberId, UUID.randomUUID(), body(recordId, "한 번만 쓰는 기록 코스", gapped(126.9100)));
        assertThat(first).hasStatusOk();
        UUID courseId = UUID.fromString(data(first).get("courseId").asString());

        assertError(register(memberId, UUID.randomUUID(), body(recordId, "같은 기록 두번째 코스", gapped(126.9100))),
                HttpStatus.CONFLICT, "COURSE-010");

        // 코스가 지워져도 그 기록은 다시 쓰지 않는다
        jdbcTemplate.update("UPDATE course.courses SET status = 'DELETED', status_reason = 'USER_DELETED', hidden_at = now() WHERE id = ?",
                courseId);
        assertError(preview(recordId, gapped(126.9100)), HttpStatus.CONFLICT, "COURSE-010");
        assertError(register(memberId, UUID.randomUUID(), body(recordId, "지운 뒤 다시 코스", gapped(126.9100))),
                HttpStatus.CONFLICT, "COURSE-010");
        assertThat(quota(memberId)).bodyJson().extractingPath("$.data.usedRunRecordIds").asArray().hasSize(1);
    }

    @Test
    void sameIdempotencyKeyReturnsFirstResult() throws Exception {
        UUID memberId = UUID.randomUUID();
        UUID key = UUID.randomUUID();

        String first = register(memberId, key, body(UUID.randomUUID(), "GPS 멱등 확인 코스", gapped(126.9150)))
                .getResponse().getContentAsString();
        MvcTestResult again = register(memberId, key, body(UUID.randomUUID(), "GPS 다른 이름 코스", gapped(126.9150)));

        assertThat(again).hasStatusOk();
        assertThat(again.getResponse().getContentAsString()).isEqualTo(first);
        assertThat(registeredCount(memberId)).isEqualTo(1);
    }

    @Test
    void gpsDailyLimitIsThreeAndSeparateFromCustom() {
        UUID memberId = UUID.randomUUID();
        assertThat(register(memberId, UUID.randomUUID(), body(UUID.randomUUID(), "GPS 하루 첫 코스", gapped(126.9200)))).hasStatusOk();
        assertThat(register(memberId, UUID.randomUUID(), body(UUID.randomUUID(), "GPS 하루 둘째 코스", gapped(126.9250)))).hasStatusOk();
        assertThat(register(memberId, UUID.randomUUID(), body(UUID.randomUUID(), "GPS 하루 셋째 코스", gapped(126.9300)))).hasStatusOk();

        assertError(register(memberId, UUID.randomUUID(), body(UUID.randomUUID(), "GPS 하루 넷째 코스", gapped(126.9350))),
                HttpStatus.TOO_MANY_REQUESTS, "COURSE-008");
        assertThat(quota(memberId)).bodyJson().extractingPath("$.data.gps.remaining").isEqualTo(0);
        assertThat(quota(memberId)).bodyJson().extractingPath("$.data.custom.remaining").isEqualTo(1);
    }

    @Test
    void failedGpsRegistrationConsumesNothing() {
        UUID memberId = UUID.randomUUID();
        UUID recordId = UUID.randomUUID();
        List<List<double[]>> turning = List.of(north(START_LAT, 126.9400, 600), north(lat(600), lng(126.9400, 100), 600));

        assertError(register(memberId, UUID.randomUUID(), body(recordId, "빈칸 못 잇는 코스", turning)), HttpStatus.BAD_REQUEST, "COURSE-011");

        assertThat(registeredCount(memberId)).isZero();
        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM course.gps_course_sources WHERE run_record_id = ?", Integer.class, recordId))
                .isZero();
    }

    @Test
    void rejectsGpsCourseOverlappingExistingOne() {
        assertThat(register(UUID.randomUUID(), UUID.randomUUID(), body(UUID.randomUUID(), "먼저 달린 GPS 코스", gapped(126.9450)))).hasStatusOk();

        assertError(register(UUID.randomUUID(), UUID.randomUUID(), body(UUID.randomUUID(), "같은 길 GPS 코스", gapped(126.9450))),
                HttpStatus.CONFLICT, "COURSE-007");
    }

    /** 600m 달리고 10m 끊긴 뒤 다시 600m. 이을 수 있다 */
    private static List<List<double[]>> gapped(double lng) {
        return List.of(north(START_LAT, lng, 600), north(lat(610), lng, 600));
    }

    /** (lat, lng)에서 북쪽으로 meters를 3m마다 한 점 */
    private static List<double[]> north(double lat, double lng, double meters) {
        List<double[]> points = new ArrayList<>();
        for (int d = 0; d <= meters; d += 3) {
            points.add(new double[]{lat + d / M_PER_DEG_LAT, lng});
        }
        return points;
    }

    /** 출발 위도에서 북쪽으로 meters 간 위도 */
    private static double lat(double meters) {
        return START_LAT + meters / M_PER_DEG_LAT;
    }

    /** lng에서 동쪽으로 meters 간 경도 */
    private static double lng(double lng, double meters) {
        return lng + meters / M_PER_DEG_LNG;
    }

    private static String segmentsJson(List<List<double[]>> segments) {
        StringBuilder json = new StringBuilder("[");
        for (int s = 0; s < segments.size(); s++) {
            json.append(s == 0 ? "[" : ",[");
            List<double[]> points = segments.get(s);
            for (int i = 0; i < points.size(); i++) {
                json.append(i == 0 ? "" : ",").append("""
                        {"lat": %s, "lng": %s, "accuracyM": 5.0, "altitudeM": 31.5, "altitudeAccuracyM": 3.0}"""
                        .formatted(points.get(i)[0], points.get(i)[1]));
            }
            json.append("]");
        }
        return json.append("]").toString();
    }

    private static String body(UUID recordId, String name, List<List<double[]>> segments) {
        return """
                {"sourceRunRecordId": "%s", "segments": %s, "name": "%s", "difficulty": "MEDIUM", "tags": ["RIVERSIDE"]}"""
                .formatted(recordId, segmentsJson(segments), name);
    }

    private MvcTestResult preview(UUID recordId, List<List<double[]>> segments) {
        return mvc.post().uri("/api/v1/courses/gps/route").with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString())))
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"sourceRunRecordId": "%s", "segments": %s}""".formatted(recordId, segmentsJson(segments)))
                .exchange();
    }

    private MvcTestResult register(UUID memberId, UUID key, String body) {
        return mvc.post().uri("/api/v1/courses/gps").with(jwt().jwt(j -> j.subject(memberId.toString())))
                .header("Idempotency-Key", key.toString())
                .contentType(MediaType.APPLICATION_JSON).content(body).exchange();
    }

    private MvcTestResult quota(UUID memberId) {
        return mvc.get().uri("/api/v1/courses/registration-quota").with(jwt().jwt(j -> j.subject(memberId.toString()))).exchange();
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private Integer registeredCount(UUID memberId) {
        return jdbcTemplate.query("SELECT registered_count FROM course.daily_registration_counts WHERE member_id = ? AND course_type = 'GPS'",
                (rs, rowNum) -> rs.getInt(1), memberId).stream().findFirst().orElse(0);
    }

    private static void assertError(MvcTestResult result, HttpStatus status, String code) {
        assertThat(result).hasStatus(status).bodyJson().extractingPath("$.code").isEqualTo(code);
    }
}
