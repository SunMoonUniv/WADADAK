package com.wadadak.course.internal.explore;

/** 지도를 축소했을 때 코스 수를 묶는 지역 단위(MAP-02). */
enum RegionLevel {
    /** 축척 2km보다 넓을 때. 특별·광역·특별자치시는 통째로 하나, 도는 시·군마다 하나 */
    CITY,
    /** 축척 2km부터 500m 전까지. 시·군·구마다 하나 */
    DISTRICT
}
