package com.wadadak.run.internal;

import com.wadadak.run.internal.RunContracts.Input;
import com.wadadak.run.internal.RunContracts.Kind;
import java.util.ArrayList;
import java.util.List;

/** Derived view only: a free ghost's SEGMENT_END is not the original session's end. Raw storage is untouched. */
public final class FullSessionInputs {
    private FullSessionInputs() {}
    public static List<Input> of(List<Input> raw) {
        List<Input> result = new ArrayList<>();
        for (Input p : raw) {
            if (p.kind() == Kind.SEGMENT_END) continue;
            result.add(new Input(result.size(), p.kind(), p.elapsedMs(), p.measuredAt(), p.location(), p.accuracyM(),
                    p.reason(), p.speedMps(), p.speedAccuracyMps(), p.steps(), p.durationMs(), p.sampleEndMs(),
                    p.altitudeM(), p.altitudeAccuracyM(), p.pressureHpa(), p.pressureAccuracy()));
        }
        return List.copyOf(result);
    }
}
