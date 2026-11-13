package com.wadadak.course.internal.planner;

import com.wadadak.common.config.HttpTimeouts;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.RoutedPath.RoadClassSpan;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.Duration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 길찾기 엔진(GraphHopper, 한국 OSM · 보행 프로필) 호출. 주소는 {@code app.course.planner.routing.base-url}(공용 서버는 compose의
 * {@code graphhopper} 서비스). 실패 · 타임아웃 · 길 없음(점이 도로에서 너무 멂)은 예외로 던지고, 부르는 쪽이 그 후보만 버린다.
 */
@Component
class RoutingClient {

    private final RestClient client;

    RoutingClient(@Value("${app.course.planner.routing.base-url}") String baseUrl,
                  @Value("${app.course.planner.routing.timeout}") Duration timeout) {
        this.client = RestClient.builder().baseUrl(baseUrl).requestFactory(HttpTimeouts.requestFactory(timeout)).build();
    }

    /**
     * 큰길 피하기용 비용: 큰길(trunk · primary · secondary)을 지나는 값을 5배 · 2.5배로 친다. 길을 만든 뒤 고르는 것으로는
     * 둘레가 모두 큰길일 때 피할 후보가 없어, 길을 찾을 때부터 돌아가게 한다. 값을 올리기만 하므로 LM 준비를 그대로 쓴다
     */
    private static final Map<String, Object> AVOID_ARTERIAL_MODEL = Map.of("priority", List.of(
            Map.of("if", "road_class == TRUNK || road_class == PRIMARY", "multiply_by", "0.2"),
            Map.of("else_if", "road_class == SECONDARY", "multiply_by", "0.4")));

    /** 점을 순서대로 지나는 경로. passThrough면 경유점에서 U턴하지 않는다(되돌아감이 줄어든다) */
    RoutedPath route(List<GeoPoint> points, boolean passThrough, boolean avoidArterial) {
        Map<String, Object> body = body(points, avoidArterial);
        if (passThrough) {
            body.put("pass_through", true);
        }
        return post(body);
    }

    /** 출발점으로 돌아오는 약 distanceM 길이의 경로. seed마다 다른 방향으로 만든다 */
    RoutedPath roundTrip(GeoPoint start, int distanceM, long seed, boolean avoidArterial) {
        Map<String, Object> body = body(List.of(start), avoidArterial);
        body.put("algorithm", "round_trip");
        body.put("round_trip.distance", distanceM);
        body.put("round_trip.seed", seed);
        return post(body);
    }

    /** 길찾기 서버가 응답하는지. 후보를 하나도 못 만들었을 때 길이 없는 것인지 서버 장애인지 가른다 */
    boolean healthy() {
        try {
            client.get().uri("/health").retrieve().toBodilessEntity();
            return true;
        } catch (RuntimeException e) {
            return false;
        }
    }

    private static Map<String, Object> body(List<GeoPoint> points, boolean avoidArterial) {
        Map<String, Object> body = new HashMap<>();
        body.put("profile", "foot");
        body.put("points", points.stream().map(p -> List.of(p.lng(), p.lat())).toList());
        body.put("points_encoded", false);
        body.put("instructions", false);
        body.put("details", List.of("road_class"));
        if (avoidArterial) {
            body.put("custom_model", AVOID_ARTERIAL_MODEL);
        }
        return body;
    }

    private RoutedPath post(Map<String, Object> body) {
        GhResponse response = client.post().uri("/route").contentType(MediaType.APPLICATION_JSON).body(body)
                .retrieve()
                .body(GhResponse.class);
        if (response == null || response.paths() == null || response.paths().isEmpty()) {
            throw new IllegalStateException("길찾기 응답에 경로가 없습니다.");
        }
        GhPath path = response.paths().getFirst();
        List<GeoPoint> points = path.points().coordinates().stream().map(c -> new GeoPoint(c.get(1), c.get(0))).toList();
        List<RoadClassSpan> roadClasses = path.details() == null ? List.of()
                : path.details().getOrDefault("road_class", List.of()).stream()
                .map(d -> new RoadClassSpan(((Number) d.get(0)).intValue(), ((Number) d.get(1)).intValue(), String.valueOf(d.get(2))))
                .toList();
        return new RoutedPath(points, path.distance(), roadClasses);
    }

    record GhResponse(List<GhPath> paths) {
    }

    /** points.coordinates는 [경도, 위도], details.road_class는 [시작 점, 끝 점, 종류] */
    record GhPath(double distance, GhPoints points, Map<String, List<List<Object>>> details) {
    }

    record GhPoints(List<List<Double>> coordinates) {
    }
}
