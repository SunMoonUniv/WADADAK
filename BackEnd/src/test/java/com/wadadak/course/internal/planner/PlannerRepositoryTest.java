package com.wadadak.course.internal.planner;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.Start;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import com.wadadak.course.internal.planner.PlanResult.PlanCandidate;
import com.wadadak.course.internal.planner.PlannerRepository.PoiCounts;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.LineString;
import org.locationtech.jts.geom.PrecisionModel;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static com.wadadak.course.internal.planner.PlannerRepository.PARSE;
import static com.wadadak.course.internal.planner.PlannerRepository.PLAN;
import static org.assertj.core.api.Assertions.assertThat;

@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class PlannerRepositoryTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    private static final GeometryFactory GEOMETRY = new GeometryFactory(new PrecisionModel(), 4326);
    private static final LocalDate TODAY = LocalDate.of(2026, 11, 10);
    private static final int LIMIT = 20;

    @Autowired
    PlannerRepository repository;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    PlannerLogRepository logs;

    @Test
    void rejectsOverLimit() {
        UUID member = UUID.randomUUID();
        for (int i = 0; i < LIMIT; i++) {
            assertThat(repository.reserve(member, TODAY, PLAN, LIMIT)).isTrue();
        }

        assertThat(repository.reserve(member, TODAY, PLAN, LIMIT)).isFalse();
        assertThat(repository.used(member, TODAY, PLAN)).isEqualTo(LIMIT);
    }

    @Test
    void concurrentReservesStopAtLimit() throws Exception {
        UUID member = UUID.randomUUID();
        CountDownLatch start = new CountDownLatch(1);
        List<Future<Boolean>> results = new ArrayList<>();
        try (ExecutorService pool = Executors.newFixedThreadPool(30)) {
            for (int i = 0; i < 30; i++) {
                results.add(pool.submit(() -> {
                    start.await();
                    return repository.reserve(member, TODAY, PLAN, LIMIT);
                }));
            }
            start.countDown();
            int reserved = 0;
            for (Future<Boolean> result : results) {
                reserved += result.get() ? 1 : 0;
            }

            assertThat(reserved).isEqualTo(LIMIT);
        }
        assertThat(repository.used(member, TODAY, PLAN)).isEqualTo(LIMIT);
    }

    @Test
    void releaseFreesOneAndNeverGoesBelowZero() {
        UUID member = UUID.randomUUID();
        repository.release(member, TODAY, PLAN);
        assertThat(repository.used(member, TODAY, PLAN)).isZero();

        for (int i = 0; i < LIMIT; i++) {
            repository.reserve(member, TODAY, PLAN, LIMIT);
        }
        repository.release(member, TODAY, PLAN);

        assertThat(repository.used(member, TODAY, PLAN)).isEqualTo(LIMIT - 1);
        assertThat(repository.reserve(member, TODAY, PLAN, LIMIT)).isTrue();
        assertThat(repository.reserve(member, TODAY, PLAN, LIMIT)).isFalse();

        UUID other = UUID.randomUUID();
        repository.reserve(other, TODAY, PLAN, LIMIT);
        repository.release(other, TODAY, PLAN);
        repository.release(other, TODAY, PLAN);
        assertThat(repository.used(other, TODAY, PLAN)).isZero();
    }

    @Test
    void countsPerDateAndKind() {
        UUID member = UUID.randomUUID();
        for (int i = 0; i < LIMIT; i++) {
            repository.reserve(member, TODAY, PLAN, LIMIT);
        }

        assertThat(repository.reserve(member, TODAY, PLAN, LIMIT)).isFalse();
        assertThat(repository.reserve(member, TODAY.plusDays(1), PLAN, LIMIT)).isTrue();
        assertThat(repository.reserve(member, TODAY, PARSE, 50)).isTrue();
        assertThat(repository.reserve(UUID.randomUUID(), TODAY, PLAN, LIMIT)).isTrue();
        assertThat(repository.used(member, TODAY.plusDays(1), PLAN)).isEqualTo(1);
        assertThat(repository.used(member, TODAY, PARSE)).isEqualTo(1);
    }

    @Test
    void countsStoresAndToiletsWithinMeters() {
        // 서해 바다 위 동서 약 900m 선. 시드 편의점 · 화장실이 없는 곳이다. 위도 0.00027도 ≈ 30m
        LineString route = GEOMETRY.createLineString(new Coordinate[]{
                new Coordinate(125.0000, 36.0000), new Coordinate(125.0100, 36.0000)});
        poi("test:30m", "CONVENIENCE", 125.0050, 36.00027);
        poi("test:70m", "CONVENIENCE", 125.0050, 36.00063);
        poi("test:toilet-10m", "TOILET", 125.0050, 36.00009);
        poi("test:toilet-70m", "TOILET", 125.0060, 36.00063);
        poi("test:toilet-150m", "TOILET", 125.0070, 36.00135);

        assertThat(repository.poisNear(route, 50, 100)).isEqualTo(new PoiCounts(1, 2));
        assertThat(repository.poisNear(route, 100, 50)).isEqualTo(new PoiCounts(2, 1));
    }

    @Test
    void seedLoadsConvenienceStoresAndToilets() {
        assertThat(jdbcTemplate.queryForObject(
                "SELECT count(*) FROM course.planner_pois WHERE source_id LIKE 'sbiz:%' AND kind = 'CONVENIENCE' AND base_month = '2026-09'",
                Integer.class)).isEqualTo(57_516);
        assertThat(jdbcTemplate.queryForObject(
                "SELECT count(*) FROM course.planner_pois WHERE source_id LIKE 'toilet:%' AND kind = 'TOILET' AND base_month = '2026-10'",
                Integer.class)).isEqualTo(50_643);
    }

    // --- 분석 로그

    @Test
    void planLogLinksSameMembersLatestParseWithoutIdsOrCoordinates() {
        UUID member = UUID.randomUUID();
        PlanForm form = new PlanForm(new Start(StartKind.CURRENT, null), Shape.LOOP, null, null, 5_000, null, Set.of(), null);
        logs.saveParse(member, "처음 문장", null, form, 10);
        logs.saveParse(UUID.randomUUID(), "다른 사람 문장", null, form, 10);
        logs.saveParse(member, "5km 한 바퀴", null, form, 20);
        GeoPoint here = new GeoPoint(36.7983, 127.0746);
        PlanCandidate candidate = new PlanCandidate(List.of(here, here), 5_100, 0, 0.1, 3, 0, null, null, null, null);

        logs.savePlan(member, new PlanRequest(form, here, null), PlanResult.found(List.of(candidate), null, Set.of()), 5, 300L, 7L);

        Map<String, Object> row = jdbcTemplate.queryForMap("""
                SELECT p.sentence, g.member_hash, g.candidates::text AS candidates, g.route_ms
                FROM course.planner_plan_logs g JOIN course.planner_parse_logs p ON p.id = g.parse_log_id
                WHERE g.member_hash = (SELECT member_hash FROM course.planner_parse_logs WHERE sentence = '처음 문장')""");
        // 같은 사람의 마지막 채우기와 잇는다(다른 사람 문장 · 더 이른 문장이 아니라)
        assertThat(row.get("sentence")).isEqualTo("5km 한 바퀴");
        // 회원 ID는 해시로만 남기고, 후보는 경로 점까지 전부 남긴다
        assertThat((String) row.get("member_hash")).hasSize(64).doesNotContain(member.toString());
        assertThat((String) row.get("candidates")).contains("\"distanceMeters\": 5100").contains("anchorPoints");
        assertThat(row.get("route_ms")).isEqualTo(300);
    }

    @Test
    void planLogWithoutRecentParseIsUnlinked() {
        UUID member = UUID.randomUUID();
        PlanForm form = new PlanForm(new Start(StartKind.CURRENT, null), Shape.LOOP, null, null, 5_000, null, Set.of(), null);
        logs.saveParse(member, "오래된 문장", null, form, 10);
        jdbcTemplate.update("UPDATE course.planner_parse_logs SET created_at = now() - interval '11 minutes' WHERE sentence = '오래된 문장'");

        logs.savePlan(member, new PlanRequest(form, new GeoPoint(36.7983, 127.0746), null),
                PlanResult.placeNotFound("없는 곳", null), 5, null, null);

        // 10분이 지난 채우기와는 잇지 않는다. 길을 찾지 않았으니 길찾기 시간도 비어 있다
        assertThat(jdbcTemplate.queryForObject("""
                SELECT count(*) FROM course.planner_plan_logs
                WHERE parse_log_id IS NULL AND reason = 'PLACE_NOT_FOUND' AND route_ms IS NULL""", Integer.class)).isEqualTo(1);
    }

    private void poi(String sourceId, String kind, double lng, double lat) {
        jdbcTemplate.update("""
                INSERT INTO course.planner_pois VALUES (?, ?, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, '2026-09', now(), now())""",
                sourceId, kind, lng, lat);
    }
}
