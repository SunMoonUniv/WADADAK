package com.wadadak.course.internal.planner;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import jakarta.validation.Valid;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

/**
 * 코스 자동 생성 요청. 칸끼리 맞지 않으면 COMMON-001이다.
 *
 * @param currentLocation 앱의 현재 위치. 장소 출발이면 장소 검색 기준점으로만 쓴다
 * @param paceSecPerKm    평소 페이스(초/km). 시간으로 요청할 때 거리 환산에 쓰고, 없으면 6분 30초(정책 B3-A02)
 */
record PlanRequest(@NotNull @Valid PlanForm form,
                   @NotNull GeoPoint currentLocation,
                   @Min(180) @Max(900) Integer paceSecPerKm) {

    static final int DEFAULT_PACE_SEC_PER_KM = 390;
    static final int MIN_TARGET_METERS = 1_000;
    static final int MAX_LOOP_METERS = 22_000;
    static final int MAX_TARGET_METERS = 100_000;

    /** 목표 거리(m). 거리가 있으면 그대로, 없으면 시간 × 평소 페이스. 둘 다 없으면 null(편도 · 경유) */
    Integer targetMeters() {
        if (form.distanceM() != null) {
            return form.distanceM();
        }
        if (form.durationMin() == null) {
            return null;
        }
        int pace = paceSecPerKm != null ? paceSecPerKm : DEFAULT_PACE_SEC_PER_KM;
        return (int) Math.round(form.durationMin() * 60_000.0 / pace);
    }

    // 아래 검사는 form · start가 비면 통과시킨다. 빈 값은 @NotNull이 따로 잡는다.

    @JsonIgnore
    @AssertTrue(message = "장소에서 출발하면 장소 이름이 필요합니다.")
    boolean isStartQueryPresent() {
        return !hasStart() || form.start().kind() != StartKind.PLACE || hasText(form.start().query());
    }

    @JsonIgnore
    @AssertTrue(message = "편도는 도착지, 경유는 경유지가 필요합니다.")
    boolean isPlaceForShapePresent() {
        if (form == null || form.shape() == null) {
            return true;
        }
        return switch (form.shape()) {
            case POINT_TO_POINT -> hasText(form.endQuery());
            case VIA -> hasText(form.viaQuery());
            case LOOP, OUT_AND_BACK -> true;
        };
    }

    @JsonIgnore
    @AssertTrue(message = "한 바퀴와 왕복은 거리나 시간이 필요합니다.")
    boolean isTargetPresentForRoundTrip() {
        return form == null || form.shape() == null || form.shape() == Shape.POINT_TO_POINT || form.shape() == Shape.VIA
                || targetMeters() != null;
    }

    @JsonIgnore
    @AssertTrue(message = "목표 거리는 1~100km, 한 바퀴는 22km까지입니다.")
    boolean isTargetInRange() {
        Integer target = form == null ? null : targetMeters();
        if (target == null) {
            return true;
        }
        int max = form.shape() == Shape.LOOP ? MAX_LOOP_METERS : MAX_TARGET_METERS;
        return target >= MIN_TARGET_METERS && target <= max;
    }

    private boolean hasStart() {
        return form != null && form.start() != null && form.start().kind() != null;
    }

    private static boolean hasText(String s) {
        return s != null && !s.isBlank();
    }
}
