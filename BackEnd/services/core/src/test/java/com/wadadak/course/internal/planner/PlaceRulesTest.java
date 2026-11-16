package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** 장소 고르기 · 거리 규칙. 결과는 2026-11-10 지역 검색 실제 응답(utilfile/_스크립트/course_planner/naver_hub_raw.txt)에서 옮겼다. */
class PlaceRulesTest {

    private static final GeoPoint SUNMOON = new GeoPoint(36.7983, 127.0746);
    private static final GeoPoint HANGANG = new GeoPoint(37.53591, 126.92946);
    private static final GeoPoint YEOUIDO = new GeoPoint(37.52632, 126.93483);

    @Test
    void exactNameBeatsNearerShop() {
        PlaceHit diner = new PlaceHit("한강식당", new GeoPoint(36.7990, 127.0750), true);
        PlaceHit river = new PlaceHit("한강", HANGANG, false);

        assertThat(PlaceRules.pick("한강", List.of(diner, river), SUNMOON)).contains(river);
    }

    @Test
    void landmarkBeatsShopsWhenNoExactName() {
        PlaceHit park = new PlaceHit("신정호국민관광지", new GeoPoint(36.77270, 126.98407), false);
        List<PlaceHit> hits = List.of(
                park,
                new PlaceHit("신정호수공원 전기차충전소", new GeoPoint(36.77253, 126.98286), false),
                new PlaceHit("신정식당 서산점", new GeoPoint(36.77882, 126.45203), true),
                new PlaceHit("박승광해물손칼국수 아산신정호점", new GeoPoint(36.75668, 126.97028), true),
                new PlaceHit("정직한고등어 아산신정호본점", new GeoPoint(36.76902, 126.97941), true));

        assertThat(PlaceRules.pick("신정호수공원", hits, SUNMOON)).contains(park);
    }

    @Test
    void sameNameGoesToNearest() {
        PlaceHit asan = new PlaceHit("온천천", new GeoPoint(36.78886, 126.99937), false);
        List<PlaceHit> hits = List.of(
                new PlaceHit("온천천", new GeoPoint(35.19393, 129.08777), false),
                new PlaceHit("온천천", new GeoPoint(35.19109, 129.10218), false),
                new PlaceHit("온천천", new GeoPoint(35.19890, 129.08074), false),
                asan,
                new PlaceHit("몽벨쉘터 온천천카페거리점", new GeoPoint(35.19199, 129.10066), true));

        assertThat(PlaceRules.pick("온 천천", hits, SUNMOON)).contains(asan);
    }

    @Test
    void nothingToPick() {
        assertThat(PlaceRules.pick("없는 장소", List.of(), SUNMOON)).isEmpty();
    }

    @Test
    void seoulViaFromSunmoonIsTooFar() {
        assertThat(PlaceRules.tooFar(Shape.VIA, SUNMOON, HANGANG, 10_000)).isTrue();
        assertThat(PlaceRules.tooFar(Shape.VIA, SUNMOON, HANGANG, null)).isTrue();
    }

    @Test
    void loopFromFarStartIsAllowed() {
        // 출발지(여의도)만 본다. 현재 위치(선문대)에서 80km 넘게 떨어져 있어도 된다
        assertThat(PlaceRules.tooFar(Shape.LOOP, YEOUIDO, YEOUIDO, 5_000)).isFalse();
    }

    @Test
    void oneWayAllowsFullTargetOthersHalf() {
        GeoPoint cheonan = new GeoPoint(36.77236, 127.16409); // 선문대에서 약 8.5km

        assertThat(PlaceRules.tooFar(Shape.POINT_TO_POINT, SUNMOON, cheonan, 10_000)).isFalse();
        assertThat(PlaceRules.tooFar(Shape.OUT_AND_BACK, SUNMOON, cheonan, 10_000)).isTrue();
        assertThat(PlaceRules.tooFar(Shape.POINT_TO_POINT, SUNMOON, cheonan, null)).isFalse();
    }
}
