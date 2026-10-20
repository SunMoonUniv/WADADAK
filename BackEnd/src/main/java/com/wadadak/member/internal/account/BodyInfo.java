package com.wadadak.member.internal.account;

import jakarta.persistence.Embeddable;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * 신체 정보(정책 공통 9). 선택 입력이고 네 값은 한 묶음이라, 없으면 회원 행의 네 컬럼이 모두 NULL이다.
 * 가입 요청에서 받은 값을 그대로 회원 행에 저장한다(숫자 컬럼은 SMALLINT). 출생연도 범위는 해마다 바뀌어 서비스가 확인한다.
 */
@Embeddable
public record BodyInfo(
        @NotNull @JdbcTypeCode(SqlTypes.SMALLINT) Integer birthYear,
        @NotNull @Min(100) @Max(250) @JdbcTypeCode(SqlTypes.SMALLINT) Integer heightCm,
        @NotNull @Min(20) @Max(300) @JdbcTypeCode(SqlTypes.SMALLINT) Integer weightKg,
        @NotNull @Enumerated(EnumType.STRING) Gender gender) {
}
