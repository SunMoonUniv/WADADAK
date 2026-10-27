package com.wadadak.course.internal.registration;

import com.wadadak.common.geo.GeoPoint;
import jakarta.validation.constraints.NotNull;

/**
 * 러닝 기록 경로의 한 점. 앱은 run의 course-source({@code GET /api/v1/runs/records/{id}/course-source}) 점을 그대로 보낸다.
 * 정확도 · 고도는 측정되지 않았으면 null이다. 경로에는 위도 · 경도만 쓰고, 나머지는 원본으로만 저장한다.
 */
record GpsSourcePoint(@NotNull Double lat, @NotNull Double lng, Double accuracyM, Double altitudeM, Double altitudeAccuracyM) {

    /** 범위를 벗어나면 COMMON-001({@link GeoPoint}) */
    GeoPoint location() {
        return new GeoPoint(lat, lng);
    }
}
