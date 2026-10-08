package com.wadadak.common.geo;

/**
 * WGS84(SRID 4326) 좌표. 모든 모듈의 공개 DTO·API 좌표에 쓴다. API에서는 {"lat": .., "lng": ..} 객체로 주고받는다(개발 정책 7장).
 */
public record GeoPoint(double lat, double lng) {
}
