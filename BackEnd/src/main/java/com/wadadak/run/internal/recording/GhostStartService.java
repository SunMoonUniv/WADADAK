package com.wadadak.run.internal.recording;

import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.run.internal.RunContracts.*;
import java.time.Clock;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** External course read is outside every run write transaction, including callers' transactions. */
@Service
class GhostStartService {
    private final GhostStartStore store;
    private final CourseApi courses;
    private final Clock clock;
    private final FreeGhostService freeGhosts;
    private final PublicGhostService publicGhosts;

    GhostStartService(GhostStartStore store, CourseApi courses, Clock clock, FreeGhostService freeGhosts, PublicGhostService publicGhosts) {
        this.store = store; this.courses = courses; this.clock = clock; this.freeGhosts=freeGhosts;
        this.publicGhosts=publicGhosts;
    }

    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public GhostStartApproval start(UUID owner, UUID id, GhostStart request) {
        if(request.courseId()==null) return freeGhosts.start(owner,id,request);
        var saved = store.existing(owner, id, request);
        if (saved.isPresent()) return saved.get(); // No dependency on the original record/current course on retry.
        if(request.courseVersion()==null || !"GHOST_PLAYBACK_V1".equals(request.playbackVersion()))
            throw new com.wadadak.common.exception.AppException(com.wadadak.run.RunErrorCode.INVALID);
        CourseRouteSnapshot current;
        com.wadadak.ranking.GhostCandidate candidate;
        try {
            current = courses.getRouteForRun(request.courseId());
            candidate=request.publicPeriod()==null?null:publicGhosts.candidate(owner,request.courseId(),request.publicPeriod(),request.sourceRecordId());
        } catch (RuntimeException failure) {
            // A concurrent identical request may have committed while this course read failed.
            var committed = store.existing(owner, id, request);
            if (committed.isPresent()) return committed.get();
            throw failure;
        }
        return candidate==null
            ? store.approve(owner,id,request,current,clock.instant().truncatedTo(ChronoUnit.MICROS))
            : store.approvePublic(owner,id,request,current,clock.instant().truncatedTo(ChronoUnit.MICROS),candidate);
    }
}
