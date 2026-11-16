package com.wadadak.common.entity;

import java.security.SecureRandom;
import java.util.UUID;

/**
 * UUID v7(RFC 9562) 생성. 앞 48비트가 밀리초 시각이라 PK 인덱스 단편화가 적다(개발 정책 6.1).
 */
public final class UuidV7 {

    private static final SecureRandom RANDOM = new SecureRandom();

    private UuidV7() {
    }

    public static UUID create() {
        long msb = (System.currentTimeMillis() << 16) | 0x7000L | (RANDOM.nextInt() & 0x0FFFL);
        long lsb = (RANDOM.nextLong() & 0x3FFFFFFFFFFFFFFFL) | 0x8000000000000000L;
        return new UUID(msb, lsb);
    }
}
