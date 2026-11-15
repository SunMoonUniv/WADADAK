package com.wadadak.member.internal.search;

import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.region.Region;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.storage.ObjectStorage;
import com.wadadak.member.internal.account.RunningExperience;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/** 러너 검색 SQL(G7). 닉네임 부분 일치, 검색 허용 · 활성 회원만. */
@Repository
@RequiredArgsConstructor
class RunnerSearchRepository {

    private static final String MATCH = "status = 'ACTIVE' AND profile_searchable AND strpos(lower(nickname), :key) > 0";

    /**
     * 더미 프로필 방문자 수(G7-04 인기순). 회원 ID에서 만든 0~1023 고정값이라 요청마다 순서가 같다.
     * ponytail: 실제 방문자 집계(커뮤니티 고도화)가 생기면 그 컬럼으로 바꾼다
     */
    private static final String DUMMY_VISITS = "(hashtext(id::text) & 1023)";

    private static final RowMapper<Row> ROW = (rs, rowNum) -> new Row(rs.getObject("id", UUID.class),
            rs.getString("nickname"), rs.getString("profile_image_key"), rs.getString("region_code"),
            RunningExperience.valueOf(rs.getString("running_experience")));

    private final JdbcClient jdbc;
    private final RegionDirectory regions;
    private final ObjectStorage storage;

    /** @param key {@link RunnerSearchController}로 바꾼 검색어 */
    @Transactional(readOnly = true)
    RunnerSearchResult search(String key, UUID requesterId, Cursorable page) {
        int offset = page.offset(); // 잘못된 커서는 세기 전에 거른다
        List<Row> rows = jdbc.sql("""
                        SELECT id, nickname, profile_image_key, region_code, running_experience
                        FROM member.members
                        WHERE %s
                        ORDER BY %s DESC, id
                        LIMIT :limit OFFSET :offset""".formatted(MATCH, DUMMY_VISITS))
                .param("key", key)
                .param("limit", page.size() + 1) // 하나 더 읽어 다음 쪽이 있는지 본다
                .param("offset", offset)
                .query(ROW)
                .list();
        int total = jdbc.sql("SELECT count(*) FROM member.members WHERE " + MATCH)
                .param("key", key)
                .query(Integer.class)
                .single();

        List<Row> shown = rows.subList(0, Math.min(rows.size(), page.size()));
        Map<String, Region> regionByCode = regions.findSigungus(shown.stream().map(Row::regionCode).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(Region::code, Function.identity()));
        List<RunnerSearchResult.Runner> runners = shown.stream().map(r -> new RunnerSearchResult.Runner(r.id(), r.nickname(),
                r.profileImageKey() == null ? null : storage.url(r.profileImageKey()), regionByCode.get(r.regionCode()),
                r.runningExperience(), r.id().equals(requesterId))).toList();
        return new RunnerSearchResult(total, runners, rows.size() > page.size() ? String.valueOf(offset + page.size()) : null);
    }

    private record Row(UUID id, String nickname, String profileImageKey, String regionCode,
                       RunningExperience runningExperience) {
    }
}
