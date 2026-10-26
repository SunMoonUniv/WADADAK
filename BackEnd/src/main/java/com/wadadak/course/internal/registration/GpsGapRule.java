package com.wadadak.course.internal.registration;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;

/**
 * GPS 코스 등록의 끊긴 구간 기준(정책 문서 제4부 4.1 `공통 3 GPS 등록 끊긴 구간 · B6-04`).
 *
 * <p>달리기 기록의 경로 조각(course-source {@code segments}) 사이 빈칸을 모두 직선으로 이을 수 있으면 통과다.
 * <ul>
 *   <li>앞 조각 끝과 다음 조각 시작이 20m 이하면 잇는다.</li>
 *   <li>20m를 넘으면 빈칸 앞 · 뒤의 진행 방향이 모두 두 점을 잇는 직선과 15° 안일 때만 잇는다.
 *       진행 방향은 빈칸에서 조각을 따라가며 처음으로 직선 20m 이상 떨어진 점까지의 방향이다.
 *       조각에 그런 점이 없으면(조각이 짧으면) 잇지 않는다.</li>
 * </ul>
 * 하나라도 잇지 못하면 {@code GPS 정확도 부족}이다. 빈칸 길이 상한은 없고, 경계(20m · 15°)는 통과다.
 *
 * <p>run은 {@link com.wadadak.course.CourseApi#checkGpsGaps}로 부르고, 코스 등록은 이 클래스를 바로 쓴다.
 * 기준을 바꾸면 {@link #VERSION}을 올린다. run은 저장해 둔 판단을 그 버전으로 다시 계산한다.
 */
public final class GpsGapRule {

    /** 저장한 판단이 어느 기준으로 나왔는지 남길 때 쓴다. */
    public static final String VERSION = "GPS_GAP_V1";

    /** 이 거리 이하 빈칸은 방향을 보지 않고 잇는다(m). 유사도 겹침 허용 거리와 같다. */
    static final double DIRECT_JOIN_M = 20;

    /** 진행 방향을 재는 직선 거리(m). */
    static final double DIRECTION_BASE_M = 20;

    /** 진행 방향과 빈칸 직선 사이 최대 각도(°). */
    static final double MAX_ANGLE_DEG = 15;

    private GpsGapRule() {
    }

    /**
     * @param segments 경로 조각(달린 순서). 빈 조각은 건너뛴다.
     * @return 빈칸을 모두 이을 수 있으면 true. 점이 2개보다 적으면 경로가 없어 false
     */
    public static boolean passes(List<List<GeoPoint>> segments) {
        List<List<GeoPoint>> parts = segments.stream().filter(s -> !s.isEmpty()).toList();
        if (parts.stream().mapToInt(List::size).sum() < 2) {
            return false;
        }
        for (int i = 1; i < parts.size(); i++) {
            if (!joinable(parts.get(i - 1), parts.get(i))) {
                return false;
            }
        }
        return true;
    }

    private static boolean joinable(List<GeoPoint> before, List<GeoPoint> after) {
        GeoPoint end = before.getLast();
        GeoPoint start = after.getFirst();
        if (end.distanceMeters(start) <= DIRECT_JOIN_M) {
            return true;
        }
        GeoPoint back = firstFar(before.reversed());
        GeoPoint ahead = firstFar(after);
        if (back == null || ahead == null) {
            return false;
        }
        double gap = bearing(end, start);
        return angleBetween(bearing(back, end), gap) <= MAX_ANGLE_DEG
                && angleBetween(bearing(start, ahead), gap) <= MAX_ANGLE_DEG;
    }

    /** 첫 점에서 따라가며 처음으로 직선 20m 이상 떨어진 점. 없으면 null */
    private static GeoPoint firstFar(List<GeoPoint> path) {
        GeoPoint from = path.getFirst();
        for (GeoPoint p : path) {
            if (from.distanceMeters(p) >= DIRECTION_BASE_M) {
                return p;
            }
        }
        return null;
    }

    /** from에서 to로 가는 방향(°, 북 0 · 동 90). 대권 출발 방위각 */
    static double bearing(GeoPoint from, GeoPoint to) {
        double lat1 = Math.toRadians(from.lat());
        double lat2 = Math.toRadians(to.lat());
        double dLng = Math.toRadians(to.lng() - from.lng());
        double y = Math.sin(dLng) * Math.cos(lat2);
        double x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
        return (Math.toDegrees(Math.atan2(y, x)) + 360) % 360;
    }

    /** 두 방향 사이 각도(0~180°). 355°와 5°는 10°다. */
    static double angleBetween(double a, double b) {
        double d = Math.abs(a - b) % 360;
        return d > 180 ? 360 - d : d;
    }
}
