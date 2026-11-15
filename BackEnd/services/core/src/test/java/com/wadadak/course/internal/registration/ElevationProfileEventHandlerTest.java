package com.wadadak.course.internal.registration;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseApi;
import com.wadadak.event.run.CourseRunTrackEvent;
import com.wadadak.event.run.CourseRunTrackEvent.TrackPoint;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import java.util.function.IntFunction;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/**
 * run이 보낸 완주 경로(CourseRunTrackEvent)로 만드는 고도 프로필(정책 공통 3, 정책 문서 제4부 4.1 `B1-03 고도 프로필`).
 * 완주 경로는 북쪽으로 600m를 3m마다 한 점(1초에 한 점쯤)이다.
 */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class ElevationProfileEventHandlerTest {

    private static final double M_PER_DEG_LAT = Math.PI * GeoPoint.EARTH_RADIUS_M / 180;

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    JsonMapper json;

    @Autowired
    TransactionTemplate transactionTemplate;

    @Autowired
    ApplicationEventPublisher publisher;

    @Autowired
    CourseApi courseApi;

    /** 그린 코스는 고도가 충분한 첫 완주로 한 번 만들고, 뒤에 온 완주로 바꾸지 않는다 */
    @Test
    void drawnCourseKeepsTheFirstCompletionWithEnoughAltitude() throws Exception {
        UUID course = insertCourse("CUSTOM", "ACTIVE");

        receive(track(course, i -> null)); // 고도를 못 잰 완주로는 만들지 않는다
        assertThat(profile(course).isNull()).isTrue();
        assertThat(courseApi.getRouteForRun(course).hasElevationProfile()).isFalse();

        CourseRunTrackEvent climb = track(course, i -> 30 + i * 0.15); // 600m 동안 30m에서 60m로 오른다
        receive(climb);
        receive(climb);                    // 같은 이벤트를 다시 받아도 그대로다(개발 정책 5.4)
        receive(track(course, i -> 10.0)); // 다음 완주로는 바꾸지 않는다

        JsonNode profile = profile(course);
        assertThat(profile.get("gainMeters").asInt()).isEqualTo(30);
        assertThat(profile.get("samplesMeters")).hasSize(18);
        assertThat(profile.get("samplesMeters").get(0).asDouble()).isLessThan(profile.get("samplesMeters").get(17).asDouble());
        // run은 이제 이 코스의 완주 경로를 보내지 않는다
        assertThat(courseApi.getRouteForRun(course).hasElevationProfile()).isTrue();
    }

    /** GPS 코스는 등록 기록에 고도가 부족했을 때만 완주로 만든다. 등록 기록으로 만든 프로필은 그대로다 */
    @Test
    void gpsCourseTakesACompletionOnlyWhenItsOwnRunLackedAltitude() throws Exception {
        UUID registered = insertGpsCourse(json.writeValueAsString(new ElevationProfile(5, Collections.nCopies(18, 20.0))));
        UUID lacking = insertGpsCourse("null");

        receive(track(registered, i -> 30 + i * 0.15));
        receive(track(lacking, i -> 30 + i * 0.15));

        assertThat(profile(registered).get("gainMeters").asInt()).isEqualTo(5);
        assertThat(completionProfiles(registered)).isZero();
        assertThat(profile(lacking).get("gainMeters").asInt()).isEqualTo(30);
        assertThat(courseApi.getRouteForRun(lacking).hasElevationProfile()).isTrue();
    }

    /** 공개 중이 아닌 코스 · 없는 코스의 완주는 오류 없이 버린다 */
    @Test
    void hiddenOrUnknownCourseGetsNoProfile() {
        UUID hidden = insertCourse("CUSTOM", "HIDDEN");

        receive(track(hidden, i -> 30 + i * 0.15));
        receive(track(UUID.randomUUID(), i -> 30 + i * 0.15));

        assertThat(completionProfiles(hidden)).isZero();
    }

    private void receive(Object event) {
        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(jdbc.queryForObject("SELECT count(*) FROM common.event_publication", Long.class)).isZero());
    }

    /** 북쪽으로 600m를 3m마다 한 점 간 완주 경로. [altitude]는 점 번호(0~200)마다의 고도이고 null이면 못 쟀다 */
    private static CourseRunTrackEvent track(UUID courseId, IntFunction<Double> altitude) {
        List<TrackPoint> points = new ArrayList<>();
        for (int i = 0; i <= 200; i++) {
            points.add(new TrackPoint(37.30 + i * 3 / M_PER_DEG_LAT, 127.30, 5.0, altitude.apply(i), 3.0));
        }
        return new CourseRunTrackEvent(UUID.randomUUID(), Instant.now(), UUID.randomUUID(), courseId, List.of(points));
    }

    /** 코스 상세(B1)의 고도 프로필 */
    private JsonNode profile(UUID courseId) throws Exception {
        String body = mvc.get().uri("/api/v1/courses/" + courseId).with(jwt()).exchange().getResponse().getContentAsString();
        return json.readTree(body).get("data").get("elevationProfile");
    }

    private long completionProfiles(UUID courseId) {
        return jdbc.queryForObject("SELECT count(*) FROM course.completion_elevation_profiles WHERE course_id = ?", Long.class, courseId);
    }

    /** 코스 행만 넣는다. 공개 중이 아니면 만료로 숨긴 코스다 */
    private UUID insertCourse(String type, String status) {
        UUID id = UUID.randomUUID();
        boolean active = status.equals("ACTIVE");
        jdbc.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    status_reason, hidden_at, expires_at, version, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, 'EASY', '{}'::varchar[],
                                ST_GeomFromText('LINESTRING(127.30 37.30, 127.30 37.31)', 4326), 1112,
                                ST_GeogFromText('SRID=4326;POINT(127.30 37.30)'), '1171010100', '1171000000', '1100000000',
                                ?, ?, ?, ?, 0, now(), now())""",
                id, UUID.randomUUID(), type, "고도 코스 " + id, "고도코스" + id, status, active ? null : "EXPIRED",
                active ? null : Timestamp.from(Instant.now()), Timestamp.from(Instant.now().plus(Duration.ofDays(30))));
        return id;
    }

    /** GPS 코스와 그 출처. [elevationProfileJson]이 JSON null이면 등록 기록에 고도가 부족했다 */
    private UUID insertGpsCourse(String elevationProfileJson) {
        UUID id = insertCourse("GPS", "ACTIVE");
        jdbc.update("""
                        INSERT INTO course.gps_course_sources (course_id, run_record_id, member_id, source_segments_json,
                                                               elevation_profile_json, created_at, updated_at)
                        VALUES (?, ?, ?, '[]', ?, now(), now())""",
                id, UUID.randomUUID(), UUID.randomUUID(), elevationProfileJson);
        return id;
    }
}
