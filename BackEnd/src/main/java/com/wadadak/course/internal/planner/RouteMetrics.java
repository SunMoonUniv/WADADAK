package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.RoutedPath.RoadClassSpan;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** 후보 경로 지표. 기준은 검증 스크립트({@code quality.py} · {@code gh_national.py})와 같다. */
final class RouteMetrics {

    static final double RESAMPLE_METERS = 10;
    /** 이 거리(m) 안에 경로의 다른 부분이 지나가면 같은 길이다 */
    static final double SAME_ROAD_METERS = 12;
    /** 경로를 따라 이 거리(m) 안의 점끼리는 비교하지 않는다. 짧은 U턴 · 교차로 회전을 되돌아감으로 세지 않는다 */
    static final double MIN_GAP_ALONG_ROUTE_METERS = 150;
    private static final double CELL_METERS = 50;
    static final Set<String> ARTERIAL = Set.of("trunk", "primary", "secondary");

    private RouteMetrics() {
    }

    /**
     * 같은 길을 되돌아오는 비율(0~1). 10m마다 다시 찍은 점 중, 경로를 따라 150m 넘게 떨어진 다른 점이 12m 안에 있는 점의 비율.
     * 50m 격자로 이웃 칸만 보므로 O(n)이다. 22km(한 바퀴 상한)까지는 출발점 기준 평면 근사로 충분하다.
     */
    static double retraceRatio(List<GeoPoint> points) {
        List<double[]> samples = resample(project(points), RESAMPLE_METERS);
        if (samples.isEmpty()) {
            return 0;
        }
        Map<Long, List<Integer>> grid = new HashMap<>();
        for (int i = 0; i < samples.size(); i++) {
            grid.computeIfAbsent(cell(samples.get(i)[0], samples.get(i)[1]), k -> new ArrayList<>()).add(i);
        }
        int retraced = 0;
        for (double[] p : samples) {
            if (hasSameRoadFarAlong(p, samples, grid)) {
                retraced++;
            }
        }
        return (double) retraced / samples.size();
    }

    /** 큰길(trunk · primary · secondary) 길이 ÷ 전체 길이(0~1) */
    static double arterialRatio(RoutedPath path) {
        List<GeoPoint> points = path.points();
        double[] segment = new double[Math.max(points.size() - 1, 0)];
        double total = 0;
        for (int i = 0; i < segment.length; i++) {
            segment[i] = points.get(i).distanceMeters(points.get(i + 1));
            total += segment[i];
        }
        if (total == 0) {
            return 0;
        }
        double arterial = 0;
        for (RoadClassSpan span : path.roadClasses()) {
            if (ARTERIAL.contains(span.roadClass())) {
                for (int i = Math.max(span.from(), 0); i < Math.min(span.to(), segment.length); i++) {
                    arterial += segment[i];
                }
            }
        }
        return arterial / total;
    }

    private static boolean hasSameRoadFarAlong(double[] p, List<double[]> samples, Map<Long, List<Integer>> grid) {
        long cx = (long) Math.floor(p[0] / CELL_METERS);
        long cy = (long) Math.floor(p[1] / CELL_METERS);
        for (long dx = -1; dx <= 1; dx++) {
            for (long dy = -1; dy <= 1; dy++) {
                for (int j : grid.getOrDefault(key(cx + dx, cy + dy), List.of())) {
                    double[] q = samples.get(j);
                    if (Math.abs(p[2] - q[2]) > MIN_GAP_ALONG_ROUTE_METERS && Math.hypot(p[0] - q[0], p[1] - q[1]) < SAME_ROAD_METERS) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /** 첫 점 기준 평면(m) 좌표 [x, y] */
    private static List<double[]> project(List<GeoPoint> points) {
        if (points.isEmpty()) {
            return List.of();
        }
        double lat0 = Math.toRadians(points.getFirst().lat());
        double lng0 = points.getFirst().lng();
        double r = GeoPoint.EARTH_RADIUS_M;
        return points.stream().map(p -> new double[]{
                r * Math.toRadians(p.lng() - lng0) * Math.cos(lat0),
                r * (Math.toRadians(p.lat()) - lat0)}).toList();
    }

    /** 평면(m) 좌표 경로를 따라 stepMeters마다 다시 찍은 점 [x, y, 출발부터 거리]. {@link SpotHeights}도 쓴다 */
    static List<double[]> resample(List<double[]> xy, double stepMeters) {
        List<double[]> samples = new ArrayList<>();
        double walked = 0;
        double next = 0;
        for (int i = 0; i + 1 < xy.size(); i++) {
            double[] a = xy.get(i);
            double[] b = xy.get(i + 1);
            double length = Math.hypot(b[0] - a[0], b[1] - a[1]);
            while (next < walked + length) {
                double t = (next - walked) / length;
                samples.add(new double[]{a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]), next});
                next += stepMeters;
            }
            walked += length;
        }
        return samples;
    }

    private static long cell(double x, double y) {
        return key((long) Math.floor(x / CELL_METERS), (long) Math.floor(y / CELL_METERS));
    }

    private static long key(long cx, long cy) {
        return (cx << 32) ^ (cy & 0xffffffffL);
    }
}
