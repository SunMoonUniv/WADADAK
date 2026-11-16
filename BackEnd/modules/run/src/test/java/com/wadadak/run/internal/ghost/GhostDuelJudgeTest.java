package com.wadadak.run.internal.ghost;

import com.wadadak.run.internal.RunContracts.*;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class GhostDuelJudgeTest {
    private CourseOutcome course(boolean completed, long seconds) {
        return new CourseOutcome(UUID.randomUUID(), "합성 코스", 1, 1000, completed,
                completed ? "COMPLETED" : "FINISH_NOT_REACHED", completed ? 1000 : 400,
                completed ? 100 : 40, completed ? Instant.EPOCH.plusSeconds(seconds) : null, seconds, 100, false);
    }
    private Input input(Kind kind, long ms, String reason) {
        return new Input(0, kind, ms, Instant.EPOCH.plusMillis(ms), null, null, reason);
    }
    private GhostDuelJudge.Verdict judge(boolean completed, long seconds, Input... inputs) {
        return GhostDuelJudge.judge(course(completed, seconds), List.of(inputs), 230, 230900);
    }

    @Test void completedTimeWinsLosesOrDrawsUsingServerIntegerSeconds() {
        for (var entry : List.of(new Object[]{229L, GhostVerdict.WIN}, new Object[]{230L, GhostVerdict.DRAW},
                new Object[]{231L, GhostVerdict.LOSE})) {
            var result = judge(true, (Long) entry[0], input(Kind.END, 900000, "USER"));
            assertThat(result.outcome()).isEqualTo(entry[1]);
            assertThat(result.reason()).isEqualTo(GhostVerdictReason.COMPLETED_TIME_COMPARISON);
        }
    }

    @Test void confirmedCompletionOverridesEveryInvoluntaryEndReason() {
        for (String reason : List.of("INTERRUPTED", "PERMISSION_REVOKED", "ACCOUNT_CHANGED"))
            assertThat(judge(true, 200, input(Kind.END, 900000, reason)).outcome()).isEqualTo(GhostVerdict.WIN);
    }

    @Test void voluntarySessionEndBeforeExactSourceFinishIsInvalidEvenWithinSameSecond() {
        var result = judge(false, 230, input(Kind.END, 230899, "USER"));
        assertThat(result.outcome()).isEqualTo(GhostVerdict.INVALID);
        assertThat(result.reason()).isEqualTo(GhostVerdictReason.VOLUNTARY_BEFORE_GHOST_FINISH);
    }

    @Test void voluntaryEndAtOrAfterSourceFinishLoses() {
        for (long ms : List.of(230900L, 230901L)) {
            var result = judge(false, 230, input(Kind.END, ms, "USER"));
            assertThat(result.outcome()).isEqualTo(GhostVerdict.LOSE);
            assertThat(result.reason()).isEqualTo(GhostVerdictReason.VOLUNTARY_AFTER_GHOST_FINISH);
        }
    }

    @Test void firstCourseOnlyBoundaryDecidesEvenIfFreeRunEndsAfterGhostFinish() {
        var result = judge(false, 200, input(Kind.SEGMENT_END, 200000, "COURSE_ONLY"), input(Kind.END, 900000, "USER"));
        assertThat(result.outcome()).isEqualTo(GhostVerdict.INVALID);
        assertThat(result.courseEndElapsedMs()).isEqualTo(200000);
        assertThat(result.courseEndReason()).isEqualTo("COURSE_ONLY");
    }

    @Test void courseOnlyAfterGhostFinishRemainsLossDespiteLaterProcessInterruption() {
        assertThat(judge(false, 300, input(Kind.SEGMENT_END, 300000, "COURSE_ONLY"),
                input(Kind.END, 900000, "INTERRUPTED")).outcome()).isEqualTo(GhostVerdict.LOSE);
    }

    @Test void involuntaryIncompleteIsInvalidBeforeAtAndAfterGhostFinish() {
        for (String reason : List.of("INTERRUPTED", "PERMISSION_REVOKED", "ACCOUNT_CHANGED")) {
            for (long ms : List.of(200000L, 230900L, 900000L)) {
                var result = judge(false, ms / 1000, input(Kind.END, ms, reason));
                assertThat(result.outcome()).isEqualTo(GhostVerdict.INVALID);
                assertThat(result.reason()).isEqualTo(GhostVerdictReason.INVOLUNTARY_INCOMPLETE);
            }
        }
    }

    @Test void appArrivalHintCannotMakeUnconfirmedFinishALoss() {
        var result = judge(false, 300, input(Kind.SEGMENT_END, 300000, "ROUTE_END"), input(Kind.END, 900000, "USER"));
        assertThat(result.outcome()).isEqualTo(GhostVerdict.INVALID);
        assertThat(result.reason()).isEqualTo(GhostVerdictReason.FINISH_NOT_CONFIRMED);
    }

    @Test void unknownCourseBoundaryCannotMasqueradeAsVoluntaryQuit() {
        assertThat(judge(false, 300, input(Kind.SEGMENT_END, 300000, null),
                input(Kind.END, 900000, "USER")).outcome()).isEqualTo(GhostVerdict.INVALID);
    }
}
