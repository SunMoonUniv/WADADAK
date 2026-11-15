package com.wadadak.course.internal.planner;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/** 길찾기 비용 모델 모양. 길찾기 자체는 RoutingClientIT가 본다 */
class RoutingClientTest {

    @Test
    void costModelPutsRulesAndAreasTogether() {
        assertThat(RoutingClient.costModel(false, Map.of())).isNull();

        Map<String, Object> model = RoutingClient.costModel(true,
                Map.of("river", List.of(List.of(List.of(List.of(127.0, 36.0), List.of(127.1, 36.0), List.of(127.1, 36.1), List.of(127.0, 36.0))))));

        assertThat(model.get("priority").toString()).contains("road_class == TRUNK", "!in_river");
        assertThat(model.get("areas").toString()).contains("FeatureCollection", "id=river", "MultiPolygon");
    }
}
