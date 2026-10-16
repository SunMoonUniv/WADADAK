package com.wadadak.run.internal.judging;

import com.wadadak.common.geo.GeoPoint;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * 코스 경로를 판정용 평면(m)으로 편다. 원점은 코스 출발점, x = 동, y = 북.
 * 경도 차이는 cos(출발 위도)로 줄인다(정거원통 근사). 출발점에서 10km 떨어져도 축척 오차가 약 0.1%라
 * 경로 일치 판정(수 m)에는 영향이 없다. 경로와 GPS 표본은 반드시 같은 인스턴스로 변환한다.
 */
final class RouteGeometry {

    private final double lat0;
    private final double lng0;
    private final double cosLat0;
    private final Point[] vertices;
    /** 출발점부터 각 꼭짓점까지 경로 길이(m). cumulative[0] = 0 */
    private final double[] cumulative;

    RouteGeometry(List<GeoPoint> route) {
        if (route.size() < 2) {
            throw new IllegalArgumentException("경로는 점이 2개 이상이어야 합니다.");
        }
        lat0 = route.getFirst().lat();
        lng0 = route.getFirst().lng();
        cosLat0 = Math.cos(Math.toRadians(lat0));
        vertices = route.stream().map(this::toLocal).toArray(Point[]::new);
        cumulative = new double[vertices.length];
        for (int i = 1; i < vertices.length; i++) {
            cumulative[i] = cumulative[i - 1] + vertices[i - 1].distanceTo(vertices[i]);
        }
    }

    /** 경로 전체 길이(m). 진행도·완주·리뷰 비율의 기준. PostGIS 타원체 길이({@code totalDistanceMeters})와 약 0.2% 다를 수 있다. */
    double length() {
        return cumulative[cumulative.length - 1];
    }

    /** 위도·경도 → 평면(m). x = Δ경도·cos(출발 위도)·R, y = Δ위도·R (각도는 라디안) */
    Point toLocal(GeoPoint p) {
        return new Point(
                Math.toRadians(p.lng() - lng0) * cosLat0 * GeoPoint.EARTH_RADIUS_M,
                Math.toRadians(p.lat() - lat0) * GeoPoint.EARTH_RADIUS_M);
    }

    /**
     * 선분 {@code segment}(꼭짓점 segment → segment+1)에 수선을 내린 위치.
     * t = (AP·AB) / |AB|²를 0~1로 잘라 선분 밖이면 가까운 끝점으로 본다.
     */
    Projection project(Point p, int segment) {
        Point a = vertices[segment];
        Point b = vertices[segment + 1];
        double abx = b.x() - a.x();
        double aby = b.y() - a.y();
        double lengthSq = abx * abx + aby * aby;
        double t = lengthSq == 0 ? 0 : ((p.x() - a.x()) * abx + (p.y() - a.y()) * aby) / lengthSq;
        t = Math.clamp(t, 0, 1);
        Point foot = new Point(a.x() + t * abx, a.y() + t * aby);
        return new Projection(segment, cumulative[segment] + t * Math.sqrt(lengthSq), p.distanceTo(foot));
    }

    /**
     * 경로까지 거리가 {@code tolerance} 이하인 코스상 위치 후보, s 오름차순.
     * 왕복·순환·교차 코스에서는 여럿일 수 있다. 꼭짓점에서 두 선분이 같은 s를 내면 하나로 친다.
     */
    List<Projection> candidates(Point p, double tolerance) {
        List<Projection> found = new ArrayList<>();
        for (int i = 0; i < vertices.length - 1; i++) {
            Projection projection = project(p, i);
            if (projection.d() <= tolerance) {
                found.add(projection);
            }
        }
        found.sort(Comparator.comparingDouble(Projection::s));
        List<Projection> distinct = new ArrayList<>();
        for (Projection projection : found) {
            // 꼭짓점의 s는 두 선분에서 부동소수 오차만큼 다르게 나온다
            if (distinct.isEmpty() || projection.s() - distinct.getLast().s() > 1e-6) {
                distinct.add(projection);
            }
        }
        return distinct;
    }

    /** 판정용 평면 좌표(m) */
    record Point(double x, double y) {
        double distanceTo(Point o) {
            return Math.hypot(o.x - x, o.y - y);
        }
    }

    /**
     * @param s 코스상 위치(m), 출발 0
     * @param d 경로까지 거리(m)
     */
    record Projection(int segment, double s, double d) {
    }
}
