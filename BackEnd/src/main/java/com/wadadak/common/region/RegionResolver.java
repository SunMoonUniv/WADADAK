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

    // ponytail: 경계를 단순화해서 이웃 동 사이에 틈이 생긴다. 포함하는 동이 없으면 약 100m(0.001도) 안의 가장 가까운 동을 쓴다. 해안에서 더 멀면 빈 값
    private static final double MAX_DEGREES = 0.001;

    private final JdbcTemplate jdbcTemplate;

    public Optional<String> resolveCode(double lat, double lng) {
        return jdbcTemplate.query("""
                        SELECT code
                        FROM common.region
                        WHERE ST_DWithin(boundary, ST_SetSRID(ST_MakePoint(?, ?), 4326), ?)
                        ORDER BY boundary <-> ST_SetSRID(ST_MakePoint(?, ?), 4326)
                        LIMIT 1""",
                (rs, rowNum) -> rs.getString(1), lng, lat, MAX_DEGREES, lng, lat).stream().findFirst();
    }
}
