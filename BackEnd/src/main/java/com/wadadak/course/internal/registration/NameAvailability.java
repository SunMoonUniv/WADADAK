package com.wadadak.course.internal.registration;

/**
 * @param name      표시용으로 정리한 이름(앞뒤 공백 제거, 연속 공백 한 칸). 등록 시 이 이름으로 저장된다
 * @param available 활성 코스 중 같은 이름(공백·대소문자 무시)이 없으면 {@code true}
 */
record NameAvailability(String name, boolean available) {
}
