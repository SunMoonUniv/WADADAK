package com.wadadak.course.internal.planner;

import com.wadadak.common.geo.GeoPoint;

/**
 * 장소 검색 결과 하나({@link PlaceSearch}).
 *
 * @param name     장소 이름(태그를 지우고 HTML 엔티티를 푼 것). 지오코딩 결과면 주소
 * @param location 좌표(WGS84)
 * @param shop     음식점 · 카페 · 술집 · 숙박 등 가게 분류. 이름이 비슷한 명소가 있으면 뒤로 밀린다({@link PlaceRules#pick})
 */
record PlaceHit(String name, GeoPoint location, boolean shop) {
}
