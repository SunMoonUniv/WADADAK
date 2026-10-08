package com.wadadak.common.geo;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;

/**
 * 좌표(WGS84). API·공개 DTO는 모두 이 타입으로 {@code {"lat": .., "lng": ..}}를 주고받는다(개발 정책 7장).
 * 범위를 벗어나면 거부한다. 위도·경도를 뒤바꿔 보낸 국내 좌표(lat 127)도 여기서 걸린다.
 */
public record GeoPoint(double lat, double lng) {

    public GeoPoint {
        // NaN도 거부하려고 부정형으로 비교한다.
        if (!(lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180)) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "좌표 범위를 벗어났습니다: lat=" + lat + ", lng=" + lng);
        }
    }
}
