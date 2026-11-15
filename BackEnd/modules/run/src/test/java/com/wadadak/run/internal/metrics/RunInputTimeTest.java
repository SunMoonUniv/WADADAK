package com.wadadak.run.internal.metrics;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.RunInputTime;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class RunInputTimeTest {
    final Instant start=Instant.parse("2026-10-29T00:00:00Z");
    Input gps(Instant measured) { return new Input(1,Kind.GPS,1000,measured,new GeoPoint(36,127),3.0,null); }
    @Test void extremeGpsAndControlTimesArePermanentInputErrors() {
        for (Instant time:List.of(Instant.MIN,Instant.MAX)) {
            var raw=List.of(new Input(0,Kind.START,0,start,null,null,null),gps(time),
                new Input(2,Kind.END,2000,start.plusSeconds(2),null,null,"INTERRUPTED"));
            assertThatThrownBy(()->FreeRunCalculator.calculate(start,raw)).isInstanceOf(AppException.class);
            assertThat(RunInputTime.valid(start,new Input(2,Kind.END,1000,time,null,null,"INTERRUPTED"))).isFalse();
        }
    }
    @Test void validGpsAndControlBoundariesRemainSupported() {
        Instant expected=start.plusMillis(1000);
        assertThat(RunInputTime.valid(start,gps(expected.minusSeconds(10)))).isTrue();
        assertThat(RunInputTime.valid(start,gps(expected.plusSeconds(5)))).isTrue();
        assertThat(RunInputTime.valid(start,gps(expected.minusSeconds(10).minusNanos(1)))).isFalse();
        assertThat(RunInputTime.valid(start,gps(expected.plusSeconds(5).plusNanos(1)))).isFalse();
        assertThat(RunInputTime.valid(start,new Input(2,Kind.END,1000,expected.plusSeconds(1),null,null,"INTERRUPTED"))).isTrue();
        assertThat(RunInputTime.valid(Instant.MAX,gps(Instant.MAX))).isFalse();
    }
}
