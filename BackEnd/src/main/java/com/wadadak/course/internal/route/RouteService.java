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
 * 코스 최종 경로 생성. 사용자 지정(B3-06)은 입력점을 순서대로 직선으로 잇고, GPS 주행 등록(D4)은 기록 경로 조각을 이어 점을 줄인다.
 * 등록(B4-07 · D4)에서도 앱이 보낸 경로를 그대로 믿지 않고 이것으로 다시 만든다.
 */
@Service
@RequiredArgsConstructor
public class RouteService {

    /** 입력점 최대 500개(정책 B3-01). 요청 검증(@Size)에서 쓰고, 넘으면 COMMON-001 */
    public static final int MAX_ANCHOR_POINTS = 500;
    static final int MIN_DISTANCE_METERS = 1_000;
    static final int MAX_CUSTOM_DISTANCE_METERS = 100_000;
    private static final int MARKER_INTERVAL_METERS = 1_000;
    /** GPS 경로 점 줄이기 허용 거리(m). 줄인 경로가 원래 점에서 이만큼 넘게 벗어나지 않는다 */
    static final double SIMPLIFY_TOLERANCE_METERS = 2;

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

    /**
     * GPS 주행 등록 코스의 경로(D4). 경로 조각을 달린 순서대로 잇고(조각 사이 빈칸은 직선), 모양이 2m 넘게 바뀌지 않게
     * 점을 줄인다(정책 문서 4.1 `F7 GPS 코스 등록 저장`). 거리 상한은 없다(정책 공통 3). 빈칸을 이을 수 있는지는 보지 않는다.
     */
    public GeneratedRoute generateGps(List<List<GeoPoint>> segments) {
        List<GeoPoint> joined = withoutConsecutiveDuplicates(segments.stream().flatMap(List::stream).toList());
        if (joined.size() < 2) {
            throw new AppException(CourseErrorCode.ROUTE_TOO_FEW_POINTS);
        }
        List<GeoPoint> route = simplified(joined);
        // 2m 안에 모두 모인 경로는 한 점으로 줄어든다. 1km에 한참 못 미친다
        if (route.size() < 2) {
            throw new AppException(CourseErrorCode.ROUTE_TOO_SHORT);
        }
        String line = toWkt(route);
        double length = jdbcTemplate.queryForObject("SELECT ST_Length(ST_GeogFromText(?))", Double.class, line);
        if ((int) Math.round(length) < MIN_DISTANCE_METERS) {
            throw new AppException(CourseErrorCode.ROUTE_TOO_SHORT);
        }
        return new GeneratedRoute(route, (int) Math.round(length), markers(line, length));
    }

    /**
     * Douglas-Peucker로 점을 줄인다. 1초에 한 점씩 쌓인 기록(30분에 약 1,800개)을 그대로 두면 코스 러닝 판정 · 지도 · 유사도
     * 계산이 무거워진다. 거리 기준이 미터여야 해서 유사도처럼 한국 전역 미터 좌표계(EPSG:5179)에서 줄인다. 첫 점과 끝 점은 남는다.
     */
    private List<GeoPoint> simplified(List<GeoPoint> points) {
        return jdbcTemplate.query("""
                        SELECT ST_Y(d.geom) AS lat, ST_X(d.geom) AS lng
                        FROM ST_DumpPoints(ST_Transform(ST_Simplify(ST_Transform(ST_GeomFromEWKT(?), 5179), ?), 4326)) AS d
                        ORDER BY d.path[1]""",
                (rs, rowNum) -> new GeoPoint(rs.getDouble("lat"), rs.getDouble("lng")),
                toWkt(points), SIMPLIFY_TOLERANCE_METERS);
    }

    /** 저장된 코스 경로의 1km 표지(B1-02). 등록할 때(B4-01)와 같은 계산이다. */
    public List<GeneratedRoute.DistanceMarker> distanceMarkers(List<GeoPoint> route) {
        String line = toWkt(route);
        double length = jdbcTemplate.queryForObject("SELECT ST_Length(ST_GeogFromText(?))", Double.class, line);
        return markers(line, length);
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
