package com.wadadak.course.internal.route;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseErrorCode;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

/**
 * 사용자 지정 코스의 최종 경로 생성(B3-06). 입력점을 순서대로 직선으로 잇는다.
 * 등록(B4-07)에서도 앱이 보낸 경로를 그대로 믿지 않고 이것으로 다시 만든다.
 */
@Service
@RequiredArgsConstructor
public class RouteService {

    static final int MIN_DISTANCE_METERS = 1_000;
    static final int MAX_CUSTOM_DISTANCE_METERS = 100_000;
    private static final int MARKER_INTERVAL_METERS = 1_000;

    private final JdbcTemplate jdbcTemplate;

    public GeneratedRoute generateCustom(List<GeoPoint> anchorPoints) {
        List<GeoPoint> route = withoutConsecutiveDuplicates(anchorPoints);
        if (route.size() < 2) {
            throw new AppException(CourseErrorCode.ROUTE_TOO_FEW_POINTS);
        }

        String line = toWkt(route);
        // geography라 거리는 WGS84 타원체 기준이다. 저장된 코스·러닝 판정과 같은 기준을 쓰려고 PostGIS로 계산한다.
        double length = jdbcTemplate.queryForObject("SELECT ST_Length(ST_GeogFromText(?))", Double.class, line);
        int distanceMeters = (int) Math.round(length);
        if (distanceMeters < MIN_DISTANCE_METERS) {
            throw new AppException(CourseErrorCode.ROUTE_TOO_SHORT);
        }
        if (distanceMeters > MAX_CUSTOM_DISTANCE_METERS) {
            throw new AppException(CourseErrorCode.ROUTE_TOO_LONG);
        }
        return new GeneratedRoute(route, distanceMeters, markers(line, length));
    }

    private List<GeneratedRoute.DistanceMarker> markers(String line, double length) {
        int count = (int) (length / MARKER_INTERVAL_METERS);
        // k km 지점 = 경로 길이 비율 k * 1000 / length 위치
        return jdbcTemplate.query("""
                        SELECT k, ST_Y(p::geometry) AS lat, ST_X(p::geometry) AS lng
                        FROM generate_series(1, ?) AS k,
                             LATERAL ST_LineInterpolatePoint(ST_GeogFromText(?), least(k * ?::float8 / ?, 1.0)) AS p
                        ORDER BY k""",
                (rs, rowNum) -> new GeneratedRoute.DistanceMarker(rs.getInt("k"), new GeoPoint(rs.getDouble("lat"), rs.getDouble("lng"))),
                count, line, MARKER_INTERVAL_METERS, length);
    }

    private static List<GeoPoint> withoutConsecutiveDuplicates(List<GeoPoint> points) {
        List<GeoPoint> result = new ArrayList<>();
        for (GeoPoint point : points) {
            if (result.isEmpty() || !result.getLast().equals(point)) {
                result.add(point);
            }
        }
        return result;
    }

    private static String toWkt(List<GeoPoint> points) {
        return points.stream()
                .map(p -> p.lng() + " " + p.lat())
                .collect(Collectors.joining(",", "SRID=4326;LINESTRING(", ")"));
    }
}
