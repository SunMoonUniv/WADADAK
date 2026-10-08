package com.wadadak.member;

import com.wadadak.common.exception.ErrorCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum MemberErrorCode implements ErrorCode {
    TOO_MANY_MEMBER_IDS(HttpStatus.BAD_REQUEST, "MEMBER-001", "한 번에 조회할 수 있는 회원 수를 넘었습니다."),
    INVALID_SOCIAL_TOKEN(HttpStatus.UNAUTHORIZED, "MEMBER-002", "소셜 로그인 정보를 확인할 수 없습니다."),
    INVALID_SIGNUP_TOKEN(HttpStatus.UNAUTHORIZED, "MEMBER-003", "가입 시간이 지났습니다. 다시 로그인해 주세요."),
    INVALID_REFRESH_TOKEN(HttpStatus.UNAUTHORIZED, "MEMBER-004", "로그인이 만료되었습니다. 다시 로그인해 주세요."),
    ALREADY_REGISTERED(HttpStatus.CONFLICT, "MEMBER-005", "이미 가입된 계정입니다."),
    NICKNAME_TAKEN(HttpStatus.CONFLICT, "MEMBER-006", "이미 사용 중인 닉네임입니다.");

    private final HttpStatus status;
    private final String code;
    private final String message;
}
