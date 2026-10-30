package com.wadadak.course.internal.explore;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.region.Region;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Difficulty;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.function.IntFunction;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

/**
 * 지도 범위 안 코스 조회(A2·A4·A5·A6)와 코스 검색(G1 · G6). 지도·목록·코스 수가 같은 조건을 써야 해서(MAP-07) 조건을 이곳 한 군데에서 만든다.
 * 검색은 조건만 다르고 정렬 · 쪽 · 카드는 목록과 같다. 홈 카드의 현재 러너 1분 갱신(공통 7)도 카드와 같은 값을 여기서 읽는다.
 * 평점 · 리뷰 수 · 도전 수 · 조회 수는 코스 통계(F11), 현재 러너는 현재 러너 수 복사본에서 읽는다. 행이 없는 코스는 모두 0이다.
 */
@Repository
@RequiredArgsConstructor
class CourseMapRepository {

    /** 한 번에 지도로 보내는 코스 수. 축척 500m부터 개별 코스를 보이므로(MAP-02) 화면 하나에는 넉넉하다 */
    static final int MAX_COURSES = 100;

    /** 현재 러너 수를 한 번에 물을 수 있는 코스 수 */
    static final int MAX_RUNNER_COURSES = 100;

    /** 특별·광역·특별자치시. 시 단위에서 통째로 하나로 센다. 시·도 코드 앞 2자리 → 짧은 이름 */
    private static final Map<String, String> METRO_CITIES = Map.of(
            "11", "서울", "26", "부산", "27", "대구", "28", "인천",
            "29", "광주", "30", "대전", "31", "울산", "36", "세종");

    /**
     * 옛 광주광역시의 구(동·서·남·북·광산구). 광주는 전라남도와 합쳐 전남광주통합특별시(12)가 되어 시·도 코드가 없다.
     * 통합특별시는 도처럼 시·군마다 세고, 이 구들은 옛 광주광역시 코드(29)로 묶어 '광주' 하나로 센다.
     */
    private static final Set<String> GWANGJU_DISTRICTS = Set.of(
            "1221000000", "1224000000", "1227000000", "1230000000", "1233000000");

    /** {@link #sharedSigunguName}에서 받을 지역 수. 같은 이름 지역 수(최대 5)보다 넉넉하다 */
    private static final int SHARED_NAME_LOOKUP = 20;

    /** 코스 · 코스 통계 · 현재 러너 수. 조건 · 열은 코스를 {@code c}, 통계를 {@code s}, 현재 러너 수를 {@code r}로 부른다. */
    private static final String FROM = """
            course.courses c
            LEFT JOIN course.course_stats s ON s.course_id = c.id
            LEFT JOIN course.course_active_runners r ON r.course_id = c.id""";

    /**
     * 인기순 기간(FIL-09)의 도전 수 · 조회 수 · 리뷰 수. 코스마다 일별 통계를 기간만큼 더한다. 기간에 행이 없으면 모두 NULL(0)이다.
     * 기간 조건은 [periodCondition]이 채운다. 코스마다 (course_id, stat_date) 유니크 인덱스로 찾는다.
     */
    private static final String PERIOD_JOIN = """

            LEFT JOIN LATERAL (SELECT sum(d.challenge_count) AS challenge_count, sum(d.view_count) AS view_count,
                                      sum(d.review_count) AS review_count
                               FROM course.course_daily_stats d
                               WHERE d.course_id = c.id%s) p ON true""";

    /** 전체 기간 평점. 리뷰 API처럼 소수 첫째 자리로 반올림한다. 리뷰가 없으면 NULL */
    private static final String RATING = "CASE WHEN s.review_count > 0 THEN round(s.rating_sum::numeric / s.review_count, 1) END";

    /** 목록 카드(지도 범위 안 코스도 같다)에 쓰는 열과 커서용 등록 시각. */
    private static final String LIST_COLUMNS = """
            c.id, c.name, c.distance_meters, c.difficulty, c.tags, c.course_type, c.expires_at, ST_AsBinary(c.route) AS route,
            c.created_at, %s AS average_rating, %s AS review_count, %s AS active_runners""".formatted(
            RATING, count("s", "review_count"), count("r", "active_count"));

    private final JdbcClient jdbc;
    private final RegionDirectory regionDirectory;

    /**
     * 범위 안 코스 수와 그중 [MAX_COURSES]개. 인기순(전체 기간, 도전 수 → 조회 수 → 리뷰 수 → 최신 → ID)으로 고르고 그 순서로 준다.
     * 앱은 이름표가 겹치면 앞 코스를 보인다(MAP-03).
     */
    CourseMap find(CourseMapRequest request) {
        Filter filter = Filter.of(request);
        String popular = countKeys(CourseListSort.POPULAR, "s").stream().map(key -> key + " DESC").collect(Collectors.joining(", "));
        List<Row> rows = jdbc.sql("""
                        SELECT %s, count(*) OVER () AS total
                        FROM %s
                        WHERE %s
                        ORDER BY %s, c.created_at DESC, c.id DESC
                        LIMIT :limit""".formatted(LIST_COLUMNS, FROM, filter.where(), popular))
                .params(filter.params())
                .param("limit", MAX_COURSES)
                .query((rs, rowNum) -> new Row(rs.getInt("total"), item(rs)))
                .list();
        return new CourseMap(rows.isEmpty() ? 0 : rows.getFirst().total(), rows.stream().map(Row::course).toList());
    }

    /**
     * [ids] 중 공개 중인 코스의 현재 러너 수(공통 7 · HCR-05 홈 1분 갱신). 카드의 {@code activeRunners}와 같은 값이다.
     * 없거나 공개 중이 아닌 코스는 빠진다. 코스 ID순.
     */
    List<CourseActiveRunners> activeRunners(Set<UUID> ids) {
        return jdbc.sql("""
                        SELECT c.id, %s AS active_runners
                        FROM course.courses c
                        LEFT JOIN course.course_active_runners r ON r.course_id = c.id
                        WHERE c.status = 'ACTIVE' AND c.id IN (:ids)
                        ORDER BY c.id""".formatted(count("r", "active_count")))
                .param("ids", ids)
                .query((rs, rowNum) -> new CourseActiveRunners(rs.getObject("id", UUID.class), rs.getInt("active_runners")))
                .list();
    }

    /**
     * 범위 안 코스를 출발점 지역별로 센다(A4-01). 코스가 많은 지역부터.
     * 구 단위는 지역마다 조건에 맞는 그 시·군·구 코스 전체(지도 범위 밖 포함)의 출발점 범위도 준다(A4-06).
     */
    RegionCounts countByRegion(CourseMapRequest request, RegionLevel level) {
        Filter filter = Filter.of(request);
        String key = switch (level) {
            case DISTRICT -> "c.sigungu_code";
            // 도의 시·군은 시·군·구 코드 앞 4자리가 같다(예: 수원시 장안구 41111 · 권선구 41113 → 4111)
            case CITY -> """
                    CASE WHEN c.sigungu_code IN (:gwangju) THEN '2900000000'
                         WHEN left(c.sido_code, 2) IN (:metro) THEN c.sido_code
                         ELSE left(c.sigungu_code, 4) || '000000' END""";
        };
        List<Group> groups = jdbc.sql("""
                        SELECT g.code, min(g.sigungu_code) AS sigungu_code, count(*) AS n, avg(g.lat) AS lat, avg(g.lng) AS lng
                        FROM (SELECT %s AS code, c.sigungu_code,
                                     ST_Y(c.start_point::geometry) AS lat, ST_X(c.start_point::geometry) AS lng
                              FROM %s
                              WHERE %s) g
                        GROUP BY g.code
                        ORDER BY n DESC, g.code""".formatted(key, FROM, filter.where()))
                .params(filter.params())
                .param("metro", METRO_CITIES.keySet())
                .param("gwangju", GWANGJU_DISTRICTS)
                .query((rs, rowNum) -> new Group(rs.getString("code"), rs.getString("sigungu_code"), rs.getInt("n"),
                        new GeoPoint(rs.getDouble("lat"), rs.getDouble("lng"))))
                .list();

        Map<String, Region> sigungus = regionDirectory.findSigungus(groups.stream().map(Group::sigunguCode).toList()).stream()
                .collect(Collectors.toMap(Region::code, Function.identity()));
        Map<String, RegionBounds> bounds = level == RegionLevel.DISTRICT && !groups.isEmpty()
                ? districtBounds(request, groups.stream().map(Group::code).toList())
                : Map.of();
        List<RegionCounts.RegionCount> regions = groups.stream()
                .map(g -> {
                    RegionBounds whole = bounds.get(g.code());
                    return new RegionCounts.RegionCount(g.code(), name(level, g, sigungus.get(g.sigunguCode())), g.count(),
                            g.center(), whole == null ? null : whole.southWest(), whole == null ? null : whole.northEast());
                })
                .toList();
        return new RegionCounts(groups.stream().mapToInt(Group::count).sum(), regions);
    }

    /** [codes] 시·군·구마다 [request]의 조건(지도 범위는 빼고)에 맞는 코스 전체의 출발점 범위(A4-06). */
    private Map<String, RegionBounds> districtBounds(CourseMapRequest request, List<String> codes) {
        Filter filter = Filter.of(request, false);
        return jdbc.sql("""
                        SELECT c.sigungu_code AS code, count(*) AS n,
                               min(ST_Y(c.start_point::geometry)) AS sw_lat, min(ST_X(c.start_point::geometry)) AS sw_lng,
                               max(ST_Y(c.start_point::geometry)) AS ne_lat, max(ST_X(c.start_point::geometry)) AS ne_lng
                        FROM %s
                        WHERE %s
                          AND c.sigungu_code IN (:codes)
                        GROUP BY c.sigungu_code""".formatted(FROM, filter.where()))
                .params(filter.params())
                .param("codes", codes)
                .query(CourseMapRepository::regionBounds)
                .list().stream()
                .collect(Collectors.toMap(RegionBounds::code, Function.identity()));
    }

    /**
     * 범위 안 코스 목록 한 쪽(A2 · A6). 조건은 지도 · 지역별 코스 수와 같다(MAP-07).
     * 인기순은 도전 수 · 조회 수 · 리뷰 수가 많은 코스부터, 평점순은 평점이 높은 코스부터(같으면 리뷰 수가 많은 코스, 리뷰가 없으면 맨 뒤),
     * 가까운순은 [origin]에서 출발점까지 가까운 코스부터, 최신순은 등록 시각이 늦은 코스부터, 실시간순은 러너가 많은 코스부터(같으면 인기순)다.
     * 인기순 · 평점순 · 실시간순은 앞 기준이 모두 같으면 최신순이고, 정렬 값이 모두 같으면 ID순.
     *
     * @param period 인기순 기간(FIL-09). 있으면 그 기간의 수로 정렬하고 코스는 빼지 않는다. null이면 전체 기간
     * @param origin 현재 위치. 가까운순이면 있어야 한다
     */
    CursorSlice<CourseListItem> list(CourseMapRequest request, CourseListSort sort, CourseListPeriod period, GeoPoint origin,
                                     Cursorable page) {
        return slice(Filter.of(request), sort, period, origin, page);
    }

    /**
     * 이름에 검색어가 들어간 활성 코스 한 쪽과 그 수(G1, SEA-03). 정렬은 [list]와 같다.
     *
     * @param key    {@link com.wadadak.course.internal.course.CourseName#key}로 바꾼 검색어
     * @param origin 현재 위치. 가까운순이면 있어야 한다
     */
    CourseSearchResult search(String key, CourseListSort sort, GeoPoint origin, Cursorable page) {
        Filter filter = Filter.byName(key);
        // 커서가 잘못됐으면 세기 전에 거른다
        CursorSlice<CourseListItem> slice = slice(filter, sort, null, origin, page);
        Integer total = jdbc.sql("SELECT count(*) FROM %s WHERE %s".formatted(FROM, filter.where()))
                .params(filter.params())
                .query(Integer.class)
                .single();
        return new CourseSearchResult(total, slice.content(), slice.nextCursor());
    }

    /**
     * 이름에 검색어가 들어간 활성 코스를 출발점 시·군·구별로 센다(G6, SEA-04). 코스가 많은 지역부터, 같으면 지역 코드순이다.
     * 고른 지역의 홈 목록(A2)은 같은 검색어 · 지역 조건이라 지도 범위가 그 코스들을 모두 담으면 수가 같다.
     *
     * @param key {@link com.wadadak.course.internal.course.CourseName#key}로 바꾼 검색어
     */
    CourseSearchRegions searchRegions(String key) {
        Filter filter = Filter.byName(key);
        List<RegionBounds> groups = jdbc.sql("""
                        SELECT c.sigungu_code AS code, count(*) AS n,
                               min(ST_Y(c.start_point::geometry)) AS sw_lat, min(ST_X(c.start_point::geometry)) AS sw_lng,
                               max(ST_Y(c.start_point::geometry)) AS ne_lat, max(ST_X(c.start_point::geometry)) AS ne_lng
                        FROM course.courses c
                        WHERE %s
                        GROUP BY c.sigungu_code
                        ORDER BY n DESC, c.sigungu_code""".formatted(filter.where()))
                .params(filter.params())
                .query(CourseMapRepository::regionBounds)
                .list();

        Map<String, Region> sigungus = regionDirectory.findSigungus(groups.stream().map(RegionBounds::code).toList()).stream()
                .collect(Collectors.toMap(Region::code, Function.identity()));
        Map<String, Boolean> shared = new HashMap<>();
        List<CourseSearchRegions.SearchRegion> regions = groups.stream()
                .map(g -> {
                    Region region = sigungus.get(g.code());
                    String name = region == null ? g.code()
                            : shared.computeIfAbsent(region.name(), this::sharedSigunguName) ? region.fullName() : region.name();
                    return new CourseSearchRegions.SearchRegion(g.code(), name, g.count(), g.southWest(), g.northEast());
                })
                .toList();
        return new CourseSearchRegions(regions);
    }

    /**
     * 전국에 [name]인 시·군·구가 둘 이상인가(중구 · 강서구 · 고성군 등). 같은 이름은 다섯 곳이 가장 많다.
     * 이름이 정확히 같은 지역부터 찾아 주므로 넉넉히 받아 센다.
     */
    private boolean sharedSigunguName(String name) {
        return regionDirectory.searchSigungu(name, SHARED_NAME_LOOKUP).stream().filter(r -> r.name().equals(name)).count() > 1;
    }

    /** [filter]에 맞는 코스 한 쪽. 정렬 · 기간은 [list] 설명과 같다. */
    private CursorSlice<CourseListItem> slice(Filter filter, CourseListSort sort, CourseListPeriod period, GeoPoint origin,
                                              Cursorable page) {
        CourseListCursor after = CourseListCursor.decode(page.cursor(), sort);
        Map<String, Object> params = new HashMap<>(filter.params());
        params.put("limit", page.size() + 1);
        if (after != null) {
            params.put("afterId", after.id());
        }
        String sql = switch (sort) {
            case LATEST -> {
                if (after != null) {
                    params.put("afterCreatedAt", OffsetDateTime.ofInstant(after.createdAt(), ZoneOffset.UTC));
                }
                yield """
                        SELECT %s
                        FROM %s
                        WHERE %s%s
                        ORDER BY c.created_at DESC, c.id DESC
                        LIMIT :limit""".formatted(LIST_COLUMNS, FROM, filter.where(),
                        after == null ? "" : "\n  AND (c.created_at, c.id) < (:afterCreatedAt, :afterId)");
            }
            case NEAREST -> {
                params.put("originLat", origin.lat());
                params.put("originLng", origin.lng());
                if (after != null) {
                    params.put("afterDistance", after.distanceMeters());
                }
                yield """
                        SELECT *
                        FROM (SELECT %s,
                                     ST_Distance(c.start_point, ST_SetSRID(ST_MakePoint(:originLng, :originLat), 4326)::geography) AS distance
                              FROM %s
                              WHERE %s) l%s
                        ORDER BY l.distance, l.id
                        LIMIT :limit""".formatted(LIST_COLUMNS, FROM, filter.where(),
                        after == null ? "" : "\nWHERE (l.distance, l.id) > (:afterDistance, :afterId)");
            }
            case RATING -> {
                if (after != null) {
                    CourseListCursor.RatingKey key = after.ratingKey();
                    params.put("afterRating", key.rating());
                    params.put("afterReviews", key.reviewCount());
                    params.put("afterCreatedAt", OffsetDateTime.ofInstant(key.createdAt(), ZoneOffset.UTC));
                }
                // 리뷰가 없는 코스는 평점을 -1로 두어 맨 뒤로 보낸다(평점은 1~5).
                // 정렬 값이 모두 내림차순이라 행 비교 하나로 다음 쪽을 자른다.
                yield """
                        SELECT *
                        FROM (SELECT %s, coalesce(%s, -1) AS rating_key
                              FROM %s
                              WHERE %s) l%s
                        ORDER BY l.rating_key DESC, l.review_count DESC, l.created_at DESC, l.id DESC
                        LIMIT :limit""".formatted(LIST_COLUMNS, RATING, FROM, filter.where(), after == null ? "" : """

                        WHERE (l.rating_key, l.review_count, l.created_at, l.id)
                              < (:afterRating, :afterReviews, :afterCreatedAt, :afterId)""");
            }
            case POPULAR, LIVE -> {
                // 기간(인기순만)이 있으면 일별 통계를 기간만큼 더한 수(p), 없으면 누적 통계(s)다.
                String from = period == null ? FROM : FROM + PERIOD_JOIN.formatted(periodCondition(period, params));
                List<String> keys = countKeys(sort, period == null ? "s" : "p");
                if (after != null) {
                    CourseListCursor.Counts counts = after.counts(keys.size());
                    for (int i = 0; i < keys.size(); i++) {
                        params.put("after" + i, counts.counts().get(i));
                    }
                    params.put("afterCreatedAt", OffsetDateTime.ofInstant(counts.createdAt(), ZoneOffset.UTC));
                }
                // sort_0, sort_1 … 순으로 비교한다. 모두 내림차순이라 행 비교 하나로 다음 쪽을 자른다.
                String columns = joined(keys.size(), i -> keys.get(i) + " AS sort_" + i);
                String order = joined(keys.size(), i -> "l.sort_" + i + " DESC");
                String afterRow = """

                        WHERE (%s, l.created_at, l.id)
                              < (%s, :afterCreatedAt, :afterId)""".formatted(
                        joined(keys.size(), i -> "l.sort_" + i), joined(keys.size(), i -> ":after" + i));
                yield """
                        SELECT *
                        FROM (SELECT %s, %s
                              FROM %s
                              WHERE %s) l%s
                        ORDER BY %s, l.created_at DESC, l.id DESC
                        LIMIT :limit""".formatted(LIST_COLUMNS, columns, from, filter.where(), after == null ? "" : afterRow, order);
            }
        };
        List<ListRow> rows = jdbc.sql(sql).params(params).query((rs, rowNum) -> listRow(rs, sort)).list();
        if (rows.size() <= page.size()) {
            return new CursorSlice<>(rows.stream().map(ListRow::item).toList(), null);
        }
        List<ListRow> shown = rows.subList(0, page.size());
        return new CursorSlice<>(shown.stream().map(ListRow::item).toList(), shown.getLast().cursor().encode());
    }

    /** [LIST_COLUMNS]로 읽은 줄 → 카드. 특징은 FIL-04 순서. */
    private static CourseListItem item(ResultSet rs) throws SQLException {
        List<CourseTag> tags = Arrays.stream((String[]) rs.getArray("tags").getArray())
                .map(CourseTag::valueOf)
                .sorted()
                .toList();
        BigDecimal rating = rs.getBigDecimal("average_rating");
        return new CourseListItem(rs.getObject("id", UUID.class), rs.getString("name"), rs.getInt("distance_meters"),
                Difficulty.valueOf(rs.getString("difficulty")), tags, CourseType.valueOf(rs.getString("course_type")),
                rs.getObject("expires_at", OffsetDateTime.class).toInstant(), rating == null ? null : rating.doubleValue(),
                rs.getInt("review_count"), rs.getInt("active_runners"), CourseGeometry.points(rs.getBytes("route")));
    }

    private static ListRow listRow(ResultSet rs, CourseListSort sort) throws SQLException {
        CourseListItem item = item(rs);
        UUID id = item.courseId();
        CourseListCursor cursor = switch (sort) {
            case LATEST -> CourseListCursor.latest(rs.getObject("created_at", OffsetDateTime.class).toInstant(), id);
            case NEAREST -> CourseListCursor.nearest(rs.getDouble("distance"), id);
            case RATING -> CourseListCursor.rating(rs.getBigDecimal("rating_key"), item.reviewCount(),
                    rs.getObject("created_at", OffsetDateTime.class).toInstant(), id);
            case POPULAR -> CourseListCursor.popular(counts(rs, CourseListCursor.POPULAR_COUNTS), id);
            case LIVE -> CourseListCursor.live(counts(rs, CourseListCursor.LIVE_COUNTS), id);
        };
        return new ListRow(item, cursor);
    }

    /** 인기순 · 실시간순 줄의 정렬 값(sort_0 …)과 등록 시각. */
    private static CourseListCursor.Counts counts(ResultSet rs, int size) throws SQLException {
        List<Long> counts = new ArrayList<>();
        for (int i = 0; i < size; i++) {
            counts.add(rs.getLong("sort_" + i));
        }
        return new CourseListCursor.Counts(counts, rs.getObject("created_at", OffsetDateTime.class).toInstant());
    }

    /**
     * 인기순 · 실시간순 정렬 값(앞에서부터 비교). 인기순은 도전 수 · 조회 수 · 리뷰 수(FIL-01),
     * 실시간순은 러너 수 다음 인기순과 같다. [stats]는 누적(s)이나 기간 합(p) 별칭이다.
     */
    private static List<String> countKeys(CourseListSort sort, String stats) {
        List<String> keys = new ArrayList<>();
        if (sort == CourseListSort.LIVE) {
            keys.add(count("r", "active_count"));
        }
        keys.add(count(stats, "challenge_count"));
        keys.add(count(stats, "view_count"));
        keys.add(count(stats, "review_count"));
        return keys;
    }

    /**
     * [alias]의 [column] 수. 행이 없으면 0이다. 도전 수를 세기 전(2026-10-20 도전 수 열을 더하기 전)에 시작한 기록을 지우면
     * 0 아래로 내려갈 수 있어 0으로 본다.
     */
    private static String count(String alias, String column) {
        return "GREATEST(coalesce(%s.%s, 0), 0)".formatted(alias, column);
    }

    /** 0 … [size]-1 마다 [part]를 쉼표로 잇는다. */
    private static String joined(int size, IntFunction<String> part) {
        return IntStream.range(0, size).mapToObj(part).collect(Collectors.joining(", "));
    }

    /** 일별 통계(별칭 d)의 기간 조건. 두 날짜 모두 포함한다(FIL-09). */
    private static String periodCondition(CourseListPeriod period, Map<String, Object> params) {
        StringBuilder condition = new StringBuilder();
        if (period.startDate() != null) {
            condition.append(" AND d.stat_date >= :periodStart");
            params.put("periodStart", period.startDate());
        }
        if (period.endDate() != null) {
            condition.append(" AND d.stat_date <= :periodEnd");
            params.put("periodEnd", period.endDate());
        }
        return condition.toString();
    }

    /**
     * 지도에 보일 짧은 이름. 구 단위는 이름의 마지막 말(수원시 장안구 → 장안구), 시 단위는 특별·광역시는 짧은 이름(서울 · 광주),
     * 도의 시는 '시'를 뗀 이름(의정부시 · 수원시 장안구 → 의정부 · 수원), 군은 그대로(연천군).
     */
    private static String name(RegionLevel level, Group group, Region sigungu) {
        String metro = METRO_CITIES.get(group.code().substring(0, 2));
        if (level == RegionLevel.CITY && metro != null) {
            return metro;
        }
        if (sigungu == null) {
            return group.code();
        }
        String[] words = sigungu.name().split(" ");
        if (level == RegionLevel.DISTRICT) {
            return words[words.length - 1];
        }
        String city = words[0];
        return city.endsWith("시") ? city.substring(0, city.length() - 1) : city;
    }

    private static RegionBounds regionBounds(ResultSet rs, int rowNum) throws SQLException {
        return new RegionBounds(rs.getString("code"), rs.getInt("n"),
                new GeoPoint(rs.getDouble("sw_lat"), rs.getDouble("sw_lng")),
                new GeoPoint(rs.getDouble("ne_lat"), rs.getDouble("ne_lng")));
    }

    /** 코스를 고르는 조건. 지도 범위와 필터(FIL-02~05, 값이 없는 필터는 걸지 않는다)나 검색어로 만든다. */
    private record Filter(String where, Map<String, Object> params) {

        /**
         * 코스 이름 검색(SEA-03). 이름 키에 [key]가 들어간 활성 코스. LIKE가 아니라 {@code strpos}라서 {@code %} · {@code _}를 따로 막지 않는다.
         * 부분 문자열이라 인덱스를 타지 않고 활성 코스를 모두 본다.
         */
        static Filter byName(String key) {
            return new Filter("c.status = 'ACTIVE'\n  AND strpos(c.name_key, :nameKey) > 0", Map.of("nameKey", key));
        }

        static Filter of(CourseMapRequest request) {
            return of(request, true);
        }

        /** @param inArea 지도 범위 안 코스만. 아니면 필터 · G6 조건만 건다 */
        static Filter of(CourseMapRequest request, boolean inArea) {
            List<String> conditions = new ArrayList<>(List.of("c.status = 'ACTIVE'"));
            Map<String, Object> params = new HashMap<>();
            if (inArea) {
                // 공간 인덱스로 후보를 줄이고, 위도·경도 사각형으로 정확히 자른다
                conditions.add("c.start_point && ST_MakeEnvelope(:swLng, :swLat, :neLng, :neLat, 4326)::geography");
                conditions.add("ST_Y(c.start_point::geometry) BETWEEN :swLat AND :neLat");
                conditions.add("ST_X(c.start_point::geometry) BETWEEN :swLng AND :neLng");
                params.putAll(Map.of(
                        "swLat", request.swLat(), "swLng", request.swLng(),
                        "neLat", request.neLat(), "neLng", request.neLng()));
            }
            if (request.minDistanceMeters() != null) {
                conditions.add("c.distance_meters >= :minDistance");
                params.put("minDistance", request.minDistanceMeters());
            }
            if (request.maxDistanceMeters() != null) {
                conditions.add("c.distance_meters <= :maxDistance");
                params.put("maxDistance", request.maxDistanceMeters());
            }
            if (request.difficulties() != null && !request.difficulties().isEmpty()) {
                conditions.add("c.difficulty IN (:difficulties)");
                params.put("difficulties", request.difficulties().stream().map(Enum::name).toList());
            }
            if (request.minRating() != null) {
                // 리뷰가 없으면 평점이 NULL이라 빠진다
                conditions.add(RATING + " >= :minRating");
                params.put("minRating", request.minRating());
            }
            if (request.tags() != null && !request.tags().isEmpty()) {
                conditions.add("c.tags @> ARRAY[:tags]::varchar[]");
                params.put("tags", request.tags().stream().map(Enum::name).toList());
            }
            if (request.courseType() != null) {
                conditions.add("c.course_type = :courseType");
                params.put("courseType", request.courseType().name());
            }
            // G6에서 고른 검색어 · 지역(SEA-04). 검색어는 [byName]과 같이 이름 키로 본다
            String nameKey = request.nameKey();
            if (nameKey != null) {
                conditions.add("strpos(c.name_key, :nameKey) > 0");
                params.put("nameKey", nameKey);
            }
            if (request.regionCode() != null) {
                conditions.add("c.sigungu_code = :regionCode");
                params.put("regionCode", request.regionCode());
            }
            return new Filter(String.join("\n  AND ", conditions), params);
        }
    }

    private record Row(int total, CourseListItem course) {
    }

    /** @param cursor 이 코스 다음 쪽을 가리키는 커서 */
    private record ListRow(CourseListItem item, CourseListCursor cursor) {
    }

    /** 시·군·구 하나와 조건에 맞는 그 지역 코스 수 · 출발점 범위(G6 · A4-06). */
    private record RegionBounds(String code, int count, GeoPoint southWest, GeoPoint northEast) {
    }

    /** @param sigunguCode 이 묶음의 시·군·구 하나. 이름을 찾는 데 쓴다 */
    private record Group(String code, String sigunguCode, int count, GeoPoint center) {
    }
}
