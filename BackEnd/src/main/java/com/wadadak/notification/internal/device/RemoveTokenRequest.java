package com.wadadak.notification.internal.device;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 기기 토큰 삭제 요청 본문. 토큰을 주소(쿼리)에 넣지 않고 본문으로 받는다.
 * 요청 로그(RequestLogFilter)가 주소를 그대로 남기기 때문이다.
 */
record RemoveTokenRequest(@NotBlank @Size(max = 1024) String token) {
}
