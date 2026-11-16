package com.wadadak.course.internal.course;

import com.wadadak.common.config.TimeConfig;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;

/**
 * 유지 기간(정책 공통 4). 등록일부터 30일씩 고정 구간으로 나누고, 구간마다 한 번 완주로 30일 연장한다.
 * 만료 시각은 늘 마지막 구간의 끝 날 23:59:59(Asia/Seoul)다. 등록하면 첫 구간의 끝이고, 연장할 때마다 다음 구간의 끝으로 옮긴다.
 */
public final class Retention {

    /** 등록일 포함 30일 */
    public static final int DAYS = 30;

    /** 비공개에서 삭제까지. 만료 · 등록자 삭제 모두 같다 */
    public static final Duration DELETE_AFTER = Duration.ofHours(24);

    /** 만료 임박: 만료일까지 7일 이내(D-7 ~ D-0, Asia/Seoul 날짜). G4 · G5 위 칸과 카드 강조가 같은 기준이다(정책 공통 4) */
    public static final int EXPIRING_SOON_DAYS = 7;

    private static final LocalTime LAST_SECOND = LocalTime.of(23, 59, 59);

    private Retention() {
    }

    /** 만료 시각이 이보다 이르면 만료 임박이다. 오늘이 10/30이면 11/7 00:00(Asia/Seoul), 곧 만료일 11/6(D-7)까지 */
    public static Instant expiringSoonBefore(LocalDate today) {
        return today.plusDays(EXPIRING_SOON_DAYS + 1).atStartOfDay(TimeConfig.SEOUL).toInstant();
    }

    /** 등록일 포함 {@value #DAYS}일째 23:59:59(Asia/Seoul). 10/1 등록이면 10/30 23:59:59 */
    public static Instant initialExpiresAt(LocalDate registeredOn) {
        return lastSecondOf(registeredOn.plusDays(DAYS - 1));
    }

    /** 만료일 다음 날 00:00(Asia/Seoul). 이 시각부터 만료다. 초 미만 경계도 이 기준으로 닫는다(정책 D-10) */
    public static Instant end(Instant expiresAt) {
        return expiryDate(expiresAt).plusDays(1).atStartOfDay(TimeConfig.SEOUL).toInstant();
    }

    /** 마지막 구간의 첫날 00:00(Asia/Seoul). 10/30 만료면 10/1, 11/29 만료면 10/31 */
    static Instant lastPeriodStart(Instant expiresAt) {
        return expiryDate(expiresAt).minusDays(DAYS - 1).atStartOfDay(TimeConfig.SEOUL).toInstant();
    }

    /** 현재 만료일에서 {@value #DAYS}일 뒤 23:59:59. 10/30 만료면 11/29 */
    static Instant extended(Instant expiresAt) {
        return lastSecondOf(expiryDate(expiresAt).plusDays(DAYS));
    }

    private static LocalDate expiryDate(Instant expiresAt) {
        return LocalDate.ofInstant(expiresAt, TimeConfig.SEOUL);
    }

    private static Instant lastSecondOf(LocalDate day) {
        return day.atTime(LAST_SECOND).atZone(TimeConfig.SEOUL).toInstant();
    }
}
