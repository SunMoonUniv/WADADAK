package com.wadadak.common.geo;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;

/**
 * 좌표(WGS84). API·공개 DTO는 모두 이 타입으로 {@code {"lat": .., "lng": ..}}를 주고받는다(개발 정책 7장).
 * 범위를 벗어나면 거부한다. 위도·경도를 뒤바꿔 보낸 국내 좌표(lat 127)도 여기서 걸린다.
 */
public record GeoPoint(double lat, double lng) {

    /** 지구 평균 반지름(m). 앱({@code recording_models.dart})과 같은 값 */
    public static final double EARTH_RADIUS_M = 6_371_008.8;

    public GeoPoint {
        // NaN도 거부하려고 부정형으로 비교한다.
        if (!(lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180)) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "좌표 범위를 벗어났습니다: lat=" + lat + ", lng=" + lng);
        }
    }

    /** 두 좌표 사이 거리(m), 하버사인. 앱과 같은 공식이다. */
    public double distanceMeters(GeoPoint other) {
        double lat1 = Math.toRadians(lat);
        double lat2 = Math.toRadians(other.lat);
        double h = Math.pow(Math.sin((lat2 - lat1) / 2), 2)
                + Math.cos(lat1) * Math.cos(lat2) * Math.pow(Math.sin(Math.toRadians(other.lng - lng) / 2), 2);
        // 부동소수 오차로 h가 1을 살짝 넘으면 asin이 NaN이 된다
        return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(Math.clamp(h, 0, 1)));
    }
}
