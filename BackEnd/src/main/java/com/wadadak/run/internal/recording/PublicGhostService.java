package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.ranking.GhostCandidate;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingPeriod;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
class PublicGhostService {
    private final RankingApi ranking;
    private final CourseApi courses;
    private final GhostPlaybackService replays;
    PublicGhostService(RankingApi ranking,CourseApi courses,GhostPlaybackService replays){
        this.ranking=ranking;this.courses=courses;this.replays=replays;
    }
    GhostCandidate candidate(UUID owner,UUID course,RankingPeriod period,UUID source){
        return ranking.findPublicGhostCandidate(course,period,owner,source)
            .orElseThrow(()->new AppException(RunErrorCode.GHOST_UNAVAILABLE));
    }
    @Transactional(propagation=Propagation.NOT_SUPPORTED)
    public PublicGhostPreparation prepare(UUID owner,UUID course,RankingPeriod period,UUID source){
        var current=courses.getRouteForRun(course);
        var candidate=candidate(owner,course,period,source);
        var replay=replays.publicReplay(owner,candidate);
        long sourceVersion=replay.course()==null?0:replay.course().version();
        return new PublicGhostPreparation(period,candidate,forCourse(current,replay),sourceVersion);
    }
    static GhostPlayback forCourse(CourseRouteSnapshot current,GhostPlayback replay){
        var source=replay.course();
        if(source==null || !current.courseId().equals(source.courseId())
            || current.totalDistanceMeters()!=source.totalDistanceMeters() || !current.route().equals(source.route()))
            throw new AppException(RunErrorCode.GHOST_UNAVAILABLE);
        // Course's optimistic entity version also changes for retention/metadata. The original
        // snapshot was already reproduced with its original version; exact ordered geometry must match.
        var reference=new CourseSnapshot(source.sessionId(),source.courseId(),source.name(),source.route(),
            source.totalDistanceMeters(),current.version(),source.breaks());
        return new GhostPlayback(replay.sourceRecordId(),reference,replay.version(),replay.sourcePolicyVersion(),
            replay.sourceCalculationVersion(),replay.courseElapsedSeconds(),replay.durationMs(),replay.eligible(),
            replay.unavailableReasons(),replay.quality(),replay.samples(),replay.spans());
    }
}
