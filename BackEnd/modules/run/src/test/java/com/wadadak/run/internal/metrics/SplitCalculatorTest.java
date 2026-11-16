package com.wadadak.run.internal.metrics;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.RunContracts.*;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

/** 구간 분석(D3·D5·D6): 1 km 랩마다 케이던스·고도 변화·누적 상승 */
class SplitCalculatorTest {
    final Instant start = Instant.parse("2026-10-12T00:00:00Z");
    static final double STEP = 3e-5; // 북쪽으로 1초에 약 3.3 m, 약 2.5 km

    /** 1 km까지 20 m 오르고, 2 km까지 10 m 내려가고, 그 뒤 평지. 걸음은 1 km까지 180 spm, 그 뒤 168 spm */
    List<Input> run(boolean altitude, boolean cadence, long gapAtIndex) {
        var inputs = new ArrayList<Input>();
        inputs.add(new Input(0, Kind.START, 0, start, null, null, "PACE_V3"));
        GeoPoint origin = new GeoPoint(36, 127);
        long nextCadence = 5000;
        long last = 0;
        for (int i = 0; i < 750; i++) {
            long ms = i * 1000L + (i >= gapAtIndex ? 90_000 : 0);
            GeoPoint at = new GeoPoint(36 + i * STEP, 127);
            double d = origin.distanceMeters(at);
            while (cadence && nextCadence <= ms) { // 1 km 도착은 약 300초(끊김은 그 뒤)
                inputs.add(new Input(inputs.size(), Kind.CADENCE, nextCadence, start.plusMillis(nextCadence), null, null, null,
                    null, null, nextCadence <= 300_000 ? 15 : 14, 5000L, nextCadence, null, null));
                nextCadence += 5000;
            }
            Double height = !altitude ? null : d <= 1000 ? 20 * d / 1000 : d <= 2000 ? 20 - 10 * (d - 1000) / 1000 : 10.0;
            inputs.add(new Input(inputs.size(), Kind.GPS, ms, start.plusMillis(ms), at, 3.0, null,
                null, null, null, null, null, height, altitude ? 3.0 : null));
            last = ms;
        }
        inputs.add(new Input(inputs.size(), Kind.END, last + 1000, start.plusMillis(last + 1000), null, null, "INTERRUPTED"));
        return inputs;
    }

    Splits splits(List<Input> inputs) {
        return SplitCalculator.calculate(start, inputs, FreeRunCalculator.calculate(start, inputs).laps());
    }

    @Test void eachLapGetsItsCadenceElevationChangeAndRunningGain() {
        var inputs = run(true, true, Long.MAX_VALUE);
        var laps = splits(inputs).laps();
        assertThat(laps).extracting(Split::number).containsExactly(1, 2, 3);
        assertThat(laps.get(0).cadence()).isCloseTo(180, within(1.0));
        assertThat(laps.get(1).cadence()).isCloseTo(168, within(1.0));
        assertThat(laps.get(0).elevationChangeM()).isCloseTo(20, within(1.5));
        assertThat(laps.get(1).elevationChangeM()).isCloseTo(-10, within(1.5)); // 내리막도 보인다
        assertThat(laps.get(2).elevationChangeM()).isCloseTo(0, within(1.5));
        assertThat(laps.get(0).cumulativeGainM()).isCloseTo(20, within(1.5));
        assertThat(laps.get(1).cumulativeGainM()).isGreaterThanOrEqualTo(laps.get(0).cumulativeGainM());
        // 마지막 누적 상승 = 결과 화면 상승 고도
        assertThat(laps.get(2).cumulativeGainM()).isEqualTo(FreeRunCalculator.calculate(start, inputs).stats().elevationGainM());
    }

    @Test void lapWithBrokenAltitudeHasNoChangeButKeepsCadence() {
        // 2 km 랩 안에서 GPS가 90초 끊김: 끊긴 앞뒤 높이를 잇지 않으므로 그 랩의 고도 변화는 비운다
        var laps = splits(run(true, true, 420)).laps();
        assertThat(laps.get(1).elevationChangeM()).isNull();
        assertThat(laps.get(1).cadence()).isNotNull();
        assertThat(laps.get(0).elevationChangeM()).isCloseTo(20, within(1.5));
        assertThat(laps.get(2).elevationChangeM()).isNotNull();
    }

    @Test void missingSensorsStayNull() {
        var laps = splits(run(false, false, Long.MAX_VALUE)).laps();
        assertThat(laps).hasSize(3).allSatisfy(s -> {
            assertThat(s.cadence()).isNull();
            assertThat(s.elevationChangeM()).isNull();
            assertThat(s.cumulativeGainM()).isNull();
        });
    }

    @Test void rawThatNoLongerCalculatesKeepsLapNumbersOnly() {
        var inputs = run(true, true, Long.MAX_VALUE);
        var laps = FreeRunCalculator.calculate(start, inputs).laps();
        var broken = inputs.subList(0, inputs.size() - 1); // END 없음
        assertThat(SplitCalculator.calculate(start, broken, laps).laps())
            .extracting(Split::number, Split::cadence, Split::elevationChangeM, Split::cumulativeGainM)
            .containsExactly(tuple(1, null, null, null), tuple(2, null, null, null), tuple(3, null, null, null));
    }
}
