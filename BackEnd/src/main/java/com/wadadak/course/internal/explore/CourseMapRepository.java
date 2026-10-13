package com.wadadak.course.internal.explore;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseGeometry;
import lombok.RequiredArgsConstructor;
import org.locationtech.jts.geom.LineString;
import org.locationtech.jts.io.ParseException;
import org.locationtech.jts.io.WKBReader;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 지도 범위 안 코스 조회(A2·A5). 지도·목록·코스 수가 같은 조건을 써야 해서(MAP-07) 조건을 이곳 한 군데에서 만든다.
 */
@Repository
@RequiredArgsConstructor
class CourseMapRepository {

    /** 한 번에 지도로 보내는 코스 수. 축척 500m부터 개별 코스를 보이므로(MAP-02) 화면 하나에는 넉넉하다 */
    static final int MAX_COURSES = 100;

    private final JdbcClient jdbc;

    CourseMap find(CourseMapRequest request) {
        List<String> conditions = new ArrayList<>(List.of(
                "c.status = 'ACTIVE'",
                // 공간 인덱스로 후보를 줄이고, 위도·경도 사각형으로 정확히 자른다
                "c.start_point && ST_MakeEnvelope(:swLng, :swLat, :neLng, :neLat, 4326)::geography",
                "ST_Y(c.start_point::geometry) BETWEEN :swLat AND :neLat",
                "ST_X(c.start_point::geometry) BETWEEN :swLng AND :neLng"));
        Map<String, Object> params = new HashMap<>(Map.of(
                "swLat", request.swLat(), "swLng", request.swLng(),
                "neLat", request.neLat(), "neLng", request.neLng(),
                "limit", MAX_COURSES));
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

        List<Row> rows = jdbc.sql("""
                        SELECT c.id, c.name, ST_AsBinary(c.route) AS route, count(*) OVER () AS total
                        FROM course.courses c
                        WHERE %s
                        ORDER BY c.created_at DESC, c.id DESC
                        LIMIT :limit""".formatted(String.join("\n  AND ", conditions)))
                .params(params)
                .query((rs, rowNum) -> new Row(rs.getInt("total"),
                        new CourseMap.MapCourse(rs.getObject("id", UUID.class), rs.getString("name"), points(rs.getBytes("route")))))
                .list();
        return new CourseMap(rows.isEmpty() ? 0 : rows.getFirst().total(), rows.stream().map(Row::course).toList());
    }

    private static List<GeoPoint> points(byte[] wkb) {
        try {
            return CourseGeometry.points((LineString) new WKBReader().read(wkb));
        } catch (ParseException e) {
            throw new IllegalStateException("코스 경로를 읽지 못했습니다.", e);
        }
    }

    private record Row(int total, CourseMap.MapCourse course) {
    }
}
