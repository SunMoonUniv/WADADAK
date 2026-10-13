package com.wadadak.course.internal.explore;

import com.wadadak.common.geo.GeoPoint;

import java.util.List;

/**
 * 지도 범위 안 코스를 출발점 지역별로 센 것(A4). 지도 · 목록 · 코스 수와 같은 조건이다(MAP-07).
 *
 * @param totalCount 범위 안 코스 전체 수
 * @param regions    코스가 많은 지역부터
 */
record RegionCounts(int totalCount, List<RegionCount> regions) {

    /**
     * @param code   구 단위는 시·군·구 코드. 시 단위는 특별·광역시면 시·도 코드, 도의 시·군이면 앞 4자리 뒤를 0으로 채운 코드
     * @param name   지도에 보일 짧은 이름(서울 · 의정부 · 연천군 · 성북구)
     * @param center 이 지역의 범위 안 코스 출발점들의 가운데. 개수 배지를 놓는다
     */
    record RegionCount(String code, String name, int count, GeoPoint center) {
    }
}
