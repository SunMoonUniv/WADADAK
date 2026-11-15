package com.wadadak.run.internal.ghost;

import com.wadadak.run.internal.RunContracts.*;
import java.util.List;

/** Final verdict only. Course completion is supplied by the existing server CourseJudge. */
public final class GhostDuelJudge {
    private GhostDuelJudge() {}

    public record Verdict(GhostVerdict outcome, GhostVerdictReason reason,
                          long courseEndElapsedMs, String courseEndReason) {}

    public static Verdict judge(CourseOutcome course, List<Input> inputs,
                                long sourceElapsedSeconds, long sourceDurationMs) {
        Input boundary = inputs.stream().filter(i -> i.kind() == Kind.SEGMENT_END || i.kind() == Kind.END)
                .findFirst().orElseThrow(() -> new IllegalArgumentException("Missing course boundary"));
        if (course.completed()) {
            int comparison = Long.compare(course.courseElapsedSeconds(), sourceElapsedSeconds);
            return new Verdict(comparison < 0 ? GhostVerdict.WIN : comparison > 0 ? GhostVerdict.LOSE : GhostVerdict.DRAW,
                    GhostVerdictReason.COMPLETED_TIME_COMPARISON, boundary.elapsedMs(), boundary.reason());
        }
        boolean voluntary = boundary.kind() == Kind.SEGMENT_END ? "COURSE_ONLY".equals(boundary.reason())
                : "USER".equals(boundary.reason());
        if (voluntary) {
            boolean arrived = boundary.elapsedMs() >= sourceDurationMs;
            return new Verdict(arrived ? GhostVerdict.LOSE : GhostVerdict.INVALID,
                    arrived ? GhostVerdictReason.VOLUNTARY_AFTER_GHOST_FINISH : GhostVerdictReason.VOLUNTARY_BEFORE_GHOST_FINISH,
                    boundary.elapsedMs(), boundary.reason());
        }
        // ROUTE_END is an app arrival hint, never server proof of completion or a voluntary quit.
        return new Verdict(GhostVerdict.INVALID,
                boundary.kind() == Kind.SEGMENT_END && "ROUTE_END".equals(boundary.reason())
                        ? GhostVerdictReason.FINISH_NOT_CONFIRMED : GhostVerdictReason.INVOLUNTARY_INCOMPLETE,
                boundary.elapsedMs(), boundary.reason());
    }
}
