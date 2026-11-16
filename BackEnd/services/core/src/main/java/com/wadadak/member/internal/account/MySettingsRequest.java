package com.wadadak.member.internal.account;

import jakarta.validation.constraints.NotNull;

/**
 * MY 설정(F4) "공개 여부" 두 스위치. 화면에 보이는 값 그대로 둘 다 보낸다(빠지면 COMMON-001).
 *
 * <p>{@code boolean} 대신 {@code Boolean}을 쓰는 이유: {@code boolean}은 값이 빠져도 false가 돼서
 * "안 보냄"과 "끔"을 구분하지 못한다. {@code Boolean}은 빠지면 null이라 {@code @NotNull}로 거를 수 있다.
 */
record MySettingsRequest(@NotNull Boolean infoPublic, @NotNull Boolean profileSearchable) {
}
