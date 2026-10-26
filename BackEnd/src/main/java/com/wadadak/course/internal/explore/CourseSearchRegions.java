package com.wadadak.course.internal.explore;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;

/**
 * 검색어에 걸린 코스를 출발점 시·군·구별로 센 것(G6, SEA-04). 코스가 없는 지역은 없다.
 *
 * @param regions 코스가 많은 지역부터. 같으면 지역 코드순
 */
record CourseSearchRegions(List<SearchRegion> regions) {

    /**
     * @param code      시·군·구 법정동 코드. 이 지역을 고르면 목록 · 지도에 {@code regionCode}로 보낸다(홈 A2)
     * @param name      보일 이름(영등포구 · 수원시 장안구). 전국에 같은 이름의 시·군·구가 있으면 시·도를 붙인다(서울특별시 중구)
     * @param count     이 지역에서 검색어에 걸린 코스 수
     * @param southWest 그 코스들 출발점의 남서쪽 끝. 지역을 고르면 앱이 이 범위가 보이게 지도를 옮긴다
     * @param northEast 그 코스들 출발점의 북동쪽 끝
     */
    record SearchRegion(String code, String name, int count, GeoPoint southWest, GeoPoint northEast) {
    }
}
