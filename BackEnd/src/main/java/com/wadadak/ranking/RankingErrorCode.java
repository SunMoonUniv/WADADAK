package com.wadadak.ranking;

import com.wadadak.common.exception.ErrorCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum RankingErrorCode implements ErrorCode {
    INVALID_GHOST_LIMIT(HttpStatus.BAD_REQUEST, "RANKING-001", "고스트 후보는 한 번에 1~10개까지 조회할 수 있습니다.");

    private final HttpStatus status;
    private final String code;
    private final String message;
}
