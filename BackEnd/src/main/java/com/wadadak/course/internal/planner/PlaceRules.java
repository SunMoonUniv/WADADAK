package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Shape;

import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

/** 검색 결과에서 장소 고르기 · 너무 먼 장소 거르기(정책 B3 자동 생성). */
final class PlaceRules {

    /** 목표 거리가 없을 때 출발지에서 도착지 · 경유지까지 허용하는 직선거리(m) */
    static final int NO_TARGET_LIMIT_METERS = 20_000;

    private PlaceRules() {
    }

    /**
     * 이름이 검색어와 같은 곳(공백 · 대소문자 무시) → 가게가 아닌 곳 → {@code ref}에 가까운 곳 순으로 하나 고른다.
     * 지역 검색은 좌표 조건을 받지 않아 같은 이름이 전국에서 나오므로 마지막은 거리로 가른다.
     */
    static Optional<PlaceHit> pick(String query, List<PlaceHit> hits, GeoPoint ref) {
        String wanted = normalize(query);
        return hits.stream().min(Comparator
                .comparing((PlaceHit hit) -> !normalize(hit.name()).equals(wanted))
                .thenComparing(PlaceHit::shop)
                .thenComparingDouble(hit -> hit.location().distanceMeters(ref)));
    }

    /**
     * 출발지에서 도착지 · 경유지까지 직선거리가 기준을 넘으면 너무 멀다.
     * 순환 · 왕복 · 경유는 갔다가 돌아오므로 목표의 절반, 편도는 목표, 목표가 없으면 20km다.
     * 현재 위치는 보지 않는다. 멀리 있는 곳을 출발지로 고른 코스도 만들 수 있다.
     */
    static boolean tooFar(Shape shape, GeoPoint start, GeoPoint target, Integer targetMeters) {
        double limit = targetMeters == null ? NO_TARGET_LIMIT_METERS
                : shape == Shape.POINT_TO_POINT ? targetMeters : targetMeters / 2.0;
        return start.distanceMeters(target) > limit;
    }

    private static String normalize(String name) {
        return name.replaceAll("\\s+", "").toLowerCase(Locale.ROOT);
    }
}
