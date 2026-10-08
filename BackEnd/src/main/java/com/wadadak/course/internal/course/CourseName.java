package com.wadadak.course.internal.course;

import java.text.Normalizer;
import java.util.Locale;
import java.util.regex.Pattern;

/**
 * 코스 이름 정규화. 표시용 이름과 중복 비교용 키를 나눈다.
 * 기기마다 한글이 조합형(NFD)으로 올 수 있어 먼저 NFC로 맞춘다.
 */
public final class CourseName {

    private static final Pattern WHITESPACE = Pattern.compile("\\s+");

    private CourseName() {
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
