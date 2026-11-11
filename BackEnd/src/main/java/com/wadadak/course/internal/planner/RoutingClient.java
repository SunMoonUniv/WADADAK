package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.RoutedPath.RoadClassSpan;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriBuilder;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.function.Function;

/**
 * 길찾기 엔진(GraphHopper, 한국 OSM · 보행 프로필) 호출. 주소는 {@code app.course.planner.routing.base-url}(공용 서버는 compose의
 * {@code graphhopper} 서비스). 실패 · 타임아웃 · 길 없음(점이 도로에서 너무 멂)은 예외로 던지고, 부르는 쪽이 그 후보만 버린다.
 */
@Component
class RoutingClient {

    private final RestClient client;

    RoutingClient(@Value("${app.course.planner.routing.base-url}") String baseUrl,
                  @Value("${app.course.planner.routing.timeout}") Duration timeout) {
        JdkClientHttpRequestFactory requestFactory = new JdkClientHttpRequestFactory(
                HttpClient.newBuilder().connectTimeout(timeout).build());
        requestFactory.setReadTimeout(timeout);
        this.client = RestClient.builder().baseUrl(baseUrl).requestFactory(requestFactory).build();
    }

    /** 점을 순서대로 지나는 경로. passThrough면 경유점에서 U턴하지 않는다(되돌아감이 줄어든다) */
    RoutedPath route(List<GeoPoint> points, boolean passThrough) {
        return get(uri -> {
            points.forEach(p -> uri.queryParam("point", p.lat() + "," + p.lng()));
            return passThrough ? uri.queryParam("pass_through", true) : uri;
        });
    }

    /** 출발점으로 돌아오는 약 distanceM 길이의 경로. seed마다 다른 방향으로 만든다 */
    RoutedPath roundTrip(GeoPoint start, int distanceM, long seed) {
        return get(uri -> uri.queryParam("point", start.lat() + "," + start.lng())
                .queryParam("algorithm", "round_trip")
                .queryParam("round_trip.distance", distanceM)
                .queryParam("round_trip.seed", seed));
    }

    private RoutedPath get(Function<UriBuilder, UriBuilder> params) {
        GhResponse response = client.get()
                .uri(uri -> params.apply(uri.path("/route")
                        .queryParam("profile", "foot")
                        .queryParam("points_encoded", false)
                        .queryParam("instructions", false)
                        .queryParam("details", "road_class")).build())
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
