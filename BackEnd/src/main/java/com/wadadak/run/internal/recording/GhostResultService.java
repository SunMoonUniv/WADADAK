package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.ghost.GhostDuelJudge;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class GhostResultService {
    private final GhostResultRepository results;
    private final CourseAttemptRepository attempts;
    private final FreeGhostRepository freeGhosts;

    GhostResultService(GhostResultRepository results, CourseAttemptRepository attempts, FreeGhostRepository freeGhosts) {
        this.results = results; this.attempts = attempts; this.freeGhosts=freeGhosts;
    }

    /** Called within RunService.process: summary, record, event publication and DONE commit together. */
    GhostOutcome finalizeResult(UUID id, CourseOutcome course, List<Input> inputs, Instant finalizedAt) {
        var opponent = results.opponent(id);
        if (opponent.isEmpty()) return null;
        var free=freeGhosts.find(id);
        if(free.isPresent()) {
            var r=free.get().approval().course();
            var j=new com.wadadak.run.internal.judging.CourseJudge().analyze(r.route(),r.breaks(),inputs).judgement();
            // Internal comparison only: never attach this to Result.course or publish course completion.
            course=new CourseOutcome(null,r.name(),r.version(),r.totalDistanceMeters(),j.completed(),j.reason().name(),
                j.recognizedM(),j.progressPercent(),j.completedAt(),j.courseElapsedSeconds(),j.courseMovingSeconds(),false);
        }
        if (course == null) throw new IllegalStateException("Approved ghost has no reference judgement");
        var saved = results.find(id);
        if (saved.isPresent()) return saved.get();
        var source = opponent.get();
        var verdict = GhostDuelJudge.judge(course, inputs, source.elapsedSeconds(), source.durationMs());
        GhostOutcome outcome = new GhostOutcome(free.isPresent()?"GHOST_RESULT_FREE_V1":"GHOST_RESULT_V1", id, source.sourceRecordId(), verdict.outcome(),
                verdict.reason(), course.completed(), course.courseElapsedSeconds(), source.elapsedSeconds(),
                verdict.courseEndElapsedMs(), source.durationMs(), verdict.courseEndReason(), finalizedAt);
        results.save(id, outcome);
        return outcome;
    }

    @Transactional(readOnly = true)
    public GhostOutcome get(UUID owner, UUID id) {
        if(attempts.findByIdAndMemberId(id, owner).isEmpty()
            && freeGhosts.find(id).filter(saved->owner.equals(saved.owner())).isEmpty())
            throw new AppException(RunErrorCode.NOT_FOUND);
        return results.find(id).orElseThrow(() -> new AppException(RunErrorCode.NOT_FOUND));
    }
}
