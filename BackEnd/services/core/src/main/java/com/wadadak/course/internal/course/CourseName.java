package com.wadadak.course.internal.course;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;

import java.text.Normalizer;
import java.util.Locale;
import java.util.regex.Pattern;

/**
 * 코스 이름 정규화. 표시용 이름과 중복 비교용 키를 나눈다.
 * 기기마다 한글이 조합형(NFD)으로 올 수 있어 먼저 NFC로 맞춘다.
 */
public final class CourseName {

    public static final int MIN_LENGTH = 2;
    public static final int MAX_LENGTH = 50;

    private static final Pattern WHITESPACE = Pattern.compile("\\s+");

    private CourseName() {
    }

    /**
     * 표시용으로 정리한 뒤 길이(2~50자, B4-02)를 확인한다. 글자 수는 코드 포인트로 세어 DB {@code VARCHAR(50)}과 같다.
     *
     * @return 표시용 이름
     * @throws AppException {@link CommonErrorCode#INVALID_REQUEST} — 길이 밖
     */
    public static String requireValid(String name) {
        String display = display(name);
        int length = display.codePointCount(0, display.length());
        if (length < MIN_LENGTH || length > MAX_LENGTH) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST,
                    "코스 이름은 " + MIN_LENGTH + "자 이상 " + MAX_LENGTH + "자 이하여야 합니다.");
        }
        return display;
    }

    /** 표시용: 앞뒤 공백 제거, 연속 공백은 한 칸. {@code " 한강  러닝 "} → {@code "한강 러닝"} */
    public static String display(String name) {
        return WHITESPACE.matcher(nfc(name).strip()).replaceAll(" ");
    }

    /** 중복 비교용: 공백 전부 제거, 소문자. {@code "한강 러닝"}과 {@code "한강러닝"}은 같은 키다 */
    public static String key(String name) {
        return WHITESPACE.matcher(nfc(name)).replaceAll("").toLowerCase(Locale.ROOT);
    }

    private static String nfc(String name) {
        return Normalizer.normalize(name, Normalizer.Form.NFC);
    }
}
