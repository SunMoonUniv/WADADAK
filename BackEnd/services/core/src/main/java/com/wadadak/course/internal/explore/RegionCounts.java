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
     * @param code      구 단위는 시·군·구 코드. 시 단위는 특별·광역시면 시·도 코드, 도의 시·군이면 앞 4자리 뒤를 0으로 채운 코드,
     *                  옛 광주광역시 구면 옛 광주광역시 코드(2900000000)
     * @param name      지도에 보일 짧은 이름(서울 · 광주 · 의정부 · 연천군 · 성북구)
     * @param center    이 지역의 범위 안 코스 출발점들의 가운데. 개수 배지를 놓는다
     * @param southWest 구 단위만. 이 시·군·구에서 조건에 맞는 코스 전체(지도 범위 밖 포함)의 출발점 범위. 배지를 누르면 앱이 이 범위로
     *                  지도를 맞춘다(A4-06). 시 단위는 null
     * @param northEast 구 단위만. [southWest]와 같은 범위의 북동쪽 끝. 시 단위는 null
     */
    record RegionCount(String code, String name, int count, GeoPoint center, GeoPoint southWest, GeoPoint northEast) {
    }
}
