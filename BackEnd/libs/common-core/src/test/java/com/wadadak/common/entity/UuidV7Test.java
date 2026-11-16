package com.wadadak.common.entity;

import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class UuidV7Test {

    @Test
    void isVersion7WithRfcVariant() {
        UUID id = UuidV7.create();

        assertThat(id.version()).isEqualTo(7);
        assertThat(id.variant()).isEqualTo(2);
    }

    @Test
    void startsWithCurrentMillis() throws InterruptedException {
        long before = System.currentTimeMillis();
        UUID first = UuidV7.create();
        Thread.sleep(2);
        UUID second = UuidV7.create();

        assertThat(first.getMostSignificantBits() >>> 16).isBetween(before, System.currentTimeMillis());
        assertThat(second.getMostSignificantBits() >>> 16).isGreaterThan(first.getMostSignificantBits() >>> 16);
    }
}
