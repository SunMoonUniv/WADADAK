package com.wadadak.run.internal.metrics;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.RunInputTime;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

class RunCaloriesTest {
    final Instant start = Instant.parse("2026-11-03T00:00:00Z");
    Input input(int seq, Kind kind, long ms, Double lat, Double weight) {
        return new Input(seq,kind,ms,start.plusMillis(ms),lat==null?null:new GeoPoint(lat,127),
            lat==null?null:3.0,kind==Kind.END?"USER":null,null,null,null,null,null,null,null,null,null,weight);
    }
    @Test void weightIsImmutableStartMetadataAndUsesOnlyMeasuredDistance() throws Exception {
        var inputs = List.of(input(0,Kind.START,0,null,65.0),input(1,Kind.GPS,0,36.0,null),
            input(2,Kind.GPS,1000,36.00005,null),input(3,Kind.PAUSE,1000,null,null),
            input(4,Kind.GPS,2000,37.0,null),input(5,Kind.END,3000,null,null));
        var calculated = FreeRunCalculator.calculate(start,inputs).metrics();
        assertThat(calculated.weightKg()).isEqualTo(65.0);
        assertThat(calculated.distanceM()).isBetween(5.0,6.0);
        assertThat(calculated.estimatedCaloriesKcal()).isEqualTo(65*calculated.distanceM()/1000.0);
        var json=JsonMapper.builder().findAndAddModules().build();
        assertThat(json.readValue(json.writeValueAsString(inputs.getFirst()),Input.class)).isEqualTo(inputs.getFirst());
        assertThat(json.readValue(json.writeValueAsString(calculated),Metrics.class)).isEqualTo(calculated);
    }
    @Test void noBackfillForHistoricalStartsAndInvalidWeightsCannotEnterTheStream() {
        var inputs=List.of(input(0,Kind.START,0,null,null),input(1,Kind.PAUSE,1000,null,null),input(2,Kind.END,2000,null,null));
        assertThat(FreeRunCalculator.calculate(start,inputs).metrics().estimatedCaloriesKcal()).isNull();
        for(double weight:new double[]{Double.NaN,Double.POSITIVE_INFINITY,0,19.9,300.1}) {
            assertThat(RunInputTime.valid(start,input(0,Kind.START,0,null,weight))).isFalse();
        }
        assertThat(RunInputTime.valid(start,input(1,Kind.GPS,1000,36.0,65.0))).isFalse();
    }
}
