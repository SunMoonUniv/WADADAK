package com.wadadak.course.internal.planner;

import com.wadadak.TestcontainersConfiguration;
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

    private void poi(String sourceId, String kind, double lng, double lat) {
        jdbcTemplate.update("""
                INSERT INTO course.planner_pois VALUES (?, ?, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, '2026-09', now(), now())""",
                sourceId, kind, lng, lat);
    }
}
