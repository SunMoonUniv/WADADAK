package com.wadadak.common.region;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.Optional;

/**
 * 좌표 → 읍·면·동 법정동 코드(10자리). 시·도·시·군·구 코드는 앞 2·5자리 뒤를 0으로 채워 만든다(개발 정책 2장).
 */
@Component
@RequiredArgsConstructor
public class RegionResolver {

    // ponytail: 경계를 단순화해서 이웃 동 사이에 틈·겹침이 생긴다. 포함하는 동이 없으면 약 100m(0.001도) 안의 가장 가까운 동을 쓴다. 해안에서 더 멀면 빈 값
    private static final double MAX_DEGREES = 0.001;

    private final JdbcTemplate jdbcTemplate;

    /**
     * 거리가 같으면(겹침·경계선 위) 경계에서 더 안쪽에 있는 동을, 그래도 같으면 코드가 작은 동을 골라 항상 같은 결과를 낸다.
     */
    public Optional<String> resolveCode(double lat, double lng) {
        return jdbcTemplate.query("""
                        SELECT r.code
                        FROM common.region r,
                             (SELECT ST_SetSRID(ST_MakePoint(?, ?), 4326) AS point) p
                        WHERE ST_DWithin(r.boundary, p.point, ?)
                        ORDER BY r.boundary <-> p.point, ST_Distance(ST_Boundary(r.boundary), p.point) DESC, r.code
                        LIMIT 1""",
                (rs, rowNum) -> rs.getString(1), lng, lat, MAX_DEGREES).stream().findFirst();
    }
}
