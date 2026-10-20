package com.wadadak.member.internal.account;

/** 가입 때 받는 약관 동의 항목. 신체 정보(BODY_INFO)만 선택이고 나머지는 필수다. 약관 내용을 바꾸면 버전을 올린다. */
public enum AgreementType {
    OVER_14("1"),
    SERVICE_TERMS("1"),
    PRIVACY_POLICY("1"),
    LOCATION_TERMS("1"),
    PROFILE_INFO("1"),
    BODY_INFO("1");

    final String version;

    AgreementType(String version) {
        this.version = version;
    }
}
