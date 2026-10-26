package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.ghost.GhostPlaybackBuilder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;
import java.util.List;
import java.util.UUID;

@Service
class GhostPlaybackService {
    private final RunSessionRepository sessions;
    private final RunRecordRepository records;
    private final CourseAttemptRepository attempts;
    private final RunInputRepository inputs;
    private final DeletedRunRecordRepository deletions;
    private final WithdrawnRunMemberRepository withdrawals;
    private final RunLocks locks;
    private final JsonMapper json;
    private final GhostPlaybackBuilder builder = new GhostPlaybackBuilder();

    GhostPlaybackService(RunSessionRepository sessions, RunRecordRepository records, CourseAttemptRepository attempts,
                         RunInputRepository inputs, DeletedRunRecordRepository deletions,
                         WithdrawnRunMemberRepository withdrawals, RunLocks locks, JsonMapper json) {
        this.sessions = sessions; this.records = records; this.attempts = attempts; this.inputs = inputs;
        this.deletions = deletions; this.withdrawals = withdrawals; this.locks = locks; this.json = json;
    }

    @Transactional(readOnly = true)
    public GhostPlayback own(UUID owner, UUID id) {
        // Same lock order as upload/delete/withdraw. No write, result update, or event publication.
        locks.member(owner);
        locks.session(id);
        if (withdrawals.existsById(owner) || deletions.existsById(id))
            throw new AppException(RunErrorCode.NOT_FOUND);
        sessions.findByIdAndMemberId(id, owner).orElseThrow(() -> new AppException(RunErrorCode.NOT_FOUND));
        RunRecord record = records.findById(id).orElseThrow(() -> new AppException(RunErrorCode.NOT_FOUND));
        Result source = json.readValue(record.getResultJson(), Result.class);
        if (source.course() == null || !source.course().completed())
            return builder.unavailable(source, null, "NOT_COMPLETED");
        CourseAttempt attempt = attempts.findByIdAndMemberId(id, owner).orElse(null);
        if (attempt == null) return builder.unavailable(source, null, "MISSING_COURSE_SNAPSHOT");
        List<GeoPoint> route = List.of(json.readValue(attempt.getRouteJson(), GeoPoint[].class));
        CourseSnapshot snapshot = new CourseSnapshot(id, attempt.getCourseId(), attempt.getCourseName(), route,
                attempt.getTotalDistanceMeters(), attempt.getCourseVersion());
        return builder.build(source, snapshot, inputs.findAll(id));
    }
}
