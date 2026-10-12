package com.wadadak.common.region;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;

/** 시·군·구 이름 조회·검색. 회원 활동 지역과 지역 주간 랭킹이 시·군·구 단위다(정책 공통 6). */
@Component
@RequiredArgsConstructor
public class RegionDirectory {

    private static final RowMapper<Region> REGION = (rs, rowNum) ->
            new Region(rs.getString("code"), rs.getString("name"), rs.getString("full_name"));

    private final JdbcClient jdbc;

    public Optional<Region> findSigungu(String code) {
        return jdbc.sql("SELECT code, name, full_name FROM common.region WHERE code = :code AND level = 'SIGUNGU'")
                .param("code", code)
                .query(REGION)
                .optional();
    }

    /** 이름이나 상위 구역 이름에 {@code query}가 들어간 시·군·구. 이름이 정확히 같으면 앞, 그다음 짧은 이름 순이다. */
    public List<Region> searchSigungu(String query, int limit) {
        return jdbc.sql("""
                        SELECT code, name, full_name
                        FROM common.region
                        WHERE level = 'SIGUNGU' AND (strpos(name, :query) > 0 OR strpos(full_name, :query) > 0)
                        ORDER BY name = :query DESC, length(name), code
                        LIMIT :limit""")
                .param("query", query.strip())
                .param("limit", limit)
                .query(REGION)
                .list();
    }
}
