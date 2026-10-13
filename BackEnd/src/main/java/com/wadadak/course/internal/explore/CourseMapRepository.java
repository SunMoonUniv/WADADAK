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
import org.locationtech.jts.geom.LineString;
import org.locationtech.jts.io.ParseException;
import org.locationtech.jts.io.WKBReader;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

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
import java.util.stream.Collectors;

/**
 * 지도 범위 안 코스 조회(A2·A4·A5·A6). 지도·목록·코스 수가 같은 조건을 써야 해서(MAP-07) 조건을 이곳 한 군데에서 만든다.
 */
@Repository
@RequiredArgsConstructor
class CourseMapRepository {

    /** 한 번에 지도로 보내는 코스 수. 축척 500m부터 개별 코스를 보이므로(MAP-02) 화면 하나에는 넉넉하다 */
    static final int MAX_COURSES = 100;

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

    /** 목록 카드에 쓰는 열과 최신순 커서용 등록 시각. */
    private static final String LIST_COLUMNS = """
            c.id, c.name, c.distance_meters, c.difficulty, c.tags, c.course_type, c.expires_at, ST_AsBinary(c.route) AS route,
            c.created_at""";

    private final JdbcClient jdbc;
    private final RegionDirectory regionDirectory;

    CourseMap find(CourseMapRequest request) {
        Filter filter = Filter.of(request);
        List<Row> rows = jdbc.sql("""
                        SELECT c.id, c.name, ST_AsBinary(c.route) AS route, count(*) OVER () AS total
                        FROM course.courses c
                        WHERE %s
                        ORDER BY c.created_at DESC, c.id DESC
                        LIMIT :limit""".formatted(filter.where()))
                .params(filter.params())
                .param("limit", MAX_COURSES)
                .query((rs, rowNum) -> new Row(rs.getInt("total"),
                        new CourseMap.MapCourse(rs.getObject("id", UUID.class), rs.getString("name"), points(rs.getBytes("route")))))
                .list();
        return new CourseMap(rows.isEmpty() ? 0 : rows.getFirst().total(), rows.stream().map(Row::course).toList());
    }

    /** 범위 안 코스를 출발점 지역별로 센다(A4-01). 코스가 많은 지역부터. */
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
                              FROM course.courses c
                              WHERE %s) g
                        GROUP BY g.code
                        ORDER BY n DESC, g.code""".formatted(key, filter.where()))
                .params(filter.params())
                .param("metro", METRO_CITIES.keySet())
                .param("gwangju", GWANGJU_DISTRICTS)
                .query((rs, rowNum) -> new Group(rs.getString("code"), rs.getString("sigungu_code"), rs.getInt("n"),
                        new GeoPoint(rs.getDouble("lat"), rs.getDouble("lng"))))
                .list();

        Map<String, Region> sigungus = regionDirectory.findSigungus(groups.stream().map(Group::sigunguCode).toList()).stream()
                .collect(Collectors.toMap(Region::code, Function.identity()));
        List<RegionCounts.RegionCount> regions = groups.stream()
                .map(g -> new RegionCounts.RegionCount(g.code(), name(level, g, sigungus.get(g.sigunguCode())), g.count(), g.center()))
                .toList();
        return new RegionCounts(groups.stream().mapToInt(Group::count).sum(), regions);
    }

    /**
     * 범위 안 코스 목록 한 쪽(A2 · A6). 조건은 지도 · 지역별 코스 수와 같다(MAP-07).
     * 최신순은 등록 시각이 늦은 코스부터, 가까운순은 [origin]에서 출발점까지 가까운 코스부터다. 정렬 값이 같으면 ID순.
     *
     * @param origin 현재 위치. 가까운순이면 있어야 한다
     */
    CursorSlice<CourseListItem> list(CourseMapRequest request, CourseListSort sort, GeoPoint origin, Cursorable page) {
        Filter filter = Filter.of(request);
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
                        FROM course.courses c
                        WHERE %s%s
                        ORDER BY c.created_at DESC, c.id DESC
                        LIMIT :limit""".formatted(LIST_COLUMNS, filter.where(),
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
                              FROM course.courses c
                              WHERE %s) l%s
                        ORDER BY l.distance, l.id
                        LIMIT :limit""".formatted(LIST_COLUMNS, filter.where(),
                        after == null ? "" : "\nWHERE (l.distance, l.id) > (:afterDistance, :afterId)");
            }
        };
        List<ListRow> rows = jdbc.sql(sql).params(params).query((rs, rowNum) -> listRow(rs, sort)).list();
        if (rows.size() <= page.size()) {
            return new CursorSlice<>(rows.stream().map(ListRow::item).toList(), null);
        }
        List<ListRow> shown = rows.subList(0, page.size());
        return new CursorSlice<>(shown.stream().map(ListRow::item).toList(), shown.getLast().cursor().encode());
    }

    private static ListRow listRow(ResultSet rs, CourseListSort sort) throws SQLException {
        UUID id = rs.getObject("id", UUID.class);
        List<CourseTag> tags = Arrays.stream((String[]) rs.getArray("tags").getArray())
                .map(CourseTag::valueOf)
                .sorted()
                .toList();
        CourseListItem item = new CourseListItem(id, rs.getString("name"), rs.getInt("distance_meters"),
                Difficulty.valueOf(rs.getString("difficulty")), tags, CourseType.valueOf(rs.getString("course_type")),
                rs.getObject("expires_at", OffsetDateTime.class).toInstant(), points(rs.getBytes("route")));
        CourseListCursor cursor = switch (sort) {
            case LATEST -> CourseListCursor.latest(rs.getObject("created_at", OffsetDateTime.class).toInstant(), id);
            case NEAREST -> CourseListCursor.nearest(rs.getDouble("distance"), id);
        };
        return new ListRow(item, cursor);
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

    private static List<GeoPoint> points(byte[] wkb) {
        try {
            return CourseGeometry.points((LineString) new WKBReader().read(wkb));
        } catch (ParseException e) {
            throw new IllegalStateException("코스 경로를 읽지 못했습니다.", e);
        }
    }

    /** 지도 범위와 필터(FIL-02~05)로 만든 조건. 값이 없는 필터는 걸지 않는다. */
    private record Filter(String where, Map<String, Object> params) {

        static Filter of(CourseMapRequest request) {
            List<String> conditions = new ArrayList<>(List.of(
                    "c.status = 'ACTIVE'",
                    // 공간 인덱스로 후보를 줄이고, 위도·경도 사각형으로 정확히 자른다
                    "c.start_point && ST_MakeEnvelope(:swLng, :swLat, :neLng, :neLat, 4326)::geography",
                    "ST_Y(c.start_point::geometry) BETWEEN :swLat AND :neLat",
                    "ST_X(c.start_point::geometry) BETWEEN :swLng AND :neLng"));
            Map<String, Object> params = new HashMap<>(Map.of(
                    "swLat", request.swLat(), "swLng", request.swLng(),
                    "neLat", request.neLat(), "neLng", request.neLng()));
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
            if (request.tags() != null && !request.tags().isEmpty()) {
                conditions.add("c.tags @> ARRAY[:tags]::varchar[]");
                params.put("tags", request.tags().stream().map(Enum::name).toList());
            }
            if (request.courseType() != null) {
                conditions.add("c.course_type = :courseType");
                params.put("courseType", request.courseType().name());
            }
            return new Filter(String.join("\n  AND ", conditions), params);
        }
    }

    private record Row(int total, CourseMap.MapCourse course) {
    }

    /** @param cursor 이 코스 다음 쪽을 가리키는 커서 */
    private record ListRow(CourseListItem item, CourseListCursor cursor) {
    }

    /** @param sigunguCode 이 묶음의 시·군·구 하나. 이름을 찾는 데 쓴다 */
    private record Group(String code, String sigunguCode, int count, GeoPoint center) {
    }
}
