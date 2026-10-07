package com.wadadak.member.internal;

/**
 * 가입된 회원이면 {@code tokens}, 처음이면 {@code signupRequired = true}와 가입 요청에 쓸 {@code signupToken}(1시간 유효).
 */
record LoginResponse(boolean signupRequired, String signupToken, TokenResponse tokens) {

    static LoginResponse signedIn(TokenResponse tokens) {
        return new LoginResponse(false, null, tokens);
    }

    static LoginResponse signupRequired(String signupToken) {
        return new LoginResponse(true, signupToken, null);
    }
}
