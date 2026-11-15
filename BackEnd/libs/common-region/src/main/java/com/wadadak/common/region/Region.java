package com.wadadak.common.region;

/**
 * 법정구역. 다른 모듈은 {@code code}만 저장한다(개발 정책 2장).
 *
 * @param code     법정동 코드 10자리
 * @param name     구역 이름. 예: {@code 성북구}
 * @param fullName 상위 구역을 붙인 이름. 예: {@code 서울특별시 성북구}
 */
public record Region(String code, String name, String fullName) {
}
