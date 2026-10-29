package com.wadadak.run.internal;

import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.RunContracts.Kind;
import java.time.DateTimeException;
import java.time.Duration;
import java.time.Instant;

/** Compare durations without converting untrusted timestamps to overflowing milliseconds. */
public final class RunInputTime {
    private RunInputTime() {}
    public static boolean valid(Instant start, Input input) {
        if (start == null || input == null || input.kind() == null || input.measuredAt() == null ||
            input.elapsedMs() < 0 || input.elapsedMs() > 7L * 86400000) return false;
        try {
            Duration delta = Duration.between(start.plusMillis(input.elapsedMs()), input.measuredAt());
            return input.kind() == Kind.GPS
                ? delta.compareTo(Duration.ofSeconds(-10)) >= 0 && delta.compareTo(Duration.ofSeconds(5)) <= 0
                : delta.compareTo(Duration.ofSeconds(-1)) >= 0 && delta.compareTo(Duration.ofSeconds(1)) <= 0;
        } catch (DateTimeException | ArithmeticException invalid) {
            return false;
        }
    }
}
