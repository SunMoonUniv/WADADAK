package com.wadadak.notification.internal.setting;

import jakarta.validation.constraints.NotNull;

/**
 * 알림 설정(F4). 조회 응답과 변경 요청 본문에 같이 쓴다. 지금은 하나뿐이고, 알림 종류가 늘면 필드를 더한다.
 *
 * <p>{@code Boolean}(대문자)인 이유: 변경 요청에서 값을 빠뜨리면 {@code null}이 되어 {@code @NotNull}이 잡는다.
 * 소문자 {@code boolean}이면 빠뜨린 값이 조용히 {@code false}(끄기)가 된다.
 *
 * @param courseExpiringSoon `내 코스 만료 임박`(정책 공통 4). 처음에는 켜져 있다
 */
public record NotificationSettings(@NotNull Boolean courseExpiringSoon) {

    /** 한 번도 바꾸지 않은 회원의 설정 */
    public static final NotificationSettings DEFAULT = new NotificationSettings(true);
}
