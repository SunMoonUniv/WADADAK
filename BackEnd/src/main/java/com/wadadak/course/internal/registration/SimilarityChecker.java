package com.wadadak.course.internal.registration;

import lombok.RequiredArgsConstructor;
import org.locationtech.jts.geom.LineString;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * 동일 코스 유사도(정책 공통 3) = 기존 코스와 겹치는 구간 길이 ÷ 새 코스 전체 길이.
 * 기존 활성 코스 하나씩 비교해 가장 큰 값을 쓴다. 진행 방향은 보지 않는다.
 */
@Component
@RequiredArgsConstructor
class SimilarityChecker {

    /** 새 코스 구간이 기존 경로에서 이 거리(m) 안이면 겹친 것으로 본다. 같은 길을 손으로 찍을 때의 어긋남을 흡수한다 */
    static final int OVERLAP_TOLERANCE_METERS = 20;
    static final double MAX_SIMILARITY = 0.85;

    // 공간 인덱스로 후보를 먼저 줄이는 도(degree) 단위 거리. 위도 33~38도에서 20m보다 넉넉하다(약 26~33m)
    private static final double CANDIDATE_DEGREES = 0.0003;

    private final JdbcTemplate jdbcTemplate;

    /**
     * 버퍼·교차는 한국 전역 미터 좌표계(EPSG:5179)에서 한다.
     * geography 버퍼를 geometry로 바꿔 교차하면 겹친 선이 비어 나오는 경우가 있어 쓰지 않는다.
     * 새 코스를 선분으로 나눠 겹친 길이를 더한다. 선 전체로 교차하면 같은 길을 왕복한 구간이 한 번만 세어져
     * "새 코스 전체 길이" 기준 비율보다 작게 나온다.
     *
     * @return 0~1. 겹칠 수 있는 기존 활성 코스가 없으면 0
     */
    double maxSimilarity(LineString route) {
        Double similarity = jdbcTemplate.queryForObject("""
                        WITH new AS (SELECT ST_Transform(ST_GeomFromText(?, 4326), 5179) AS g)
                        SELECT max(overlap.meters / ST_Length(new.g))
                        FROM new,
                             course.courses c,
                             LATERAL (SELECT sum(ST_Length(ST_Intersection(s.geom, ST_Buffer(ST_Transform(c.route, 5179), ?)))) AS meters
                                      FROM ST_DumpSegments(new.g) s) overlap
                        WHERE c.status = 'ACTIVE'
                          AND ST_DWithin(c.route, ST_GeomFromText(?, 4326), ?)""",
                Double.class, route.toText(), OVERLAP_TOLERANCE_METERS, route.toText(), CANDIDATE_DEGREES);
        return similarity == null ? 0 : similarity;
    }
}
