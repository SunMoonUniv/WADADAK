package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

/** All source deletion, approval, course start and event writes share run's lock order/transaction. */
@Service
class GhostStartStore {
    static final String VERSION = "GHOST_START_V1";
    private final GhostStartRepository approvals;
    private final CourseAttemptRepository attempts;
    private final RunSessionRepository sessions;
    private final DeletedRunRecordRepository deletions;
    private final WithdrawnRunMemberRepository withdrawals;
    private final RunLocks locks;
    private final GhostPlaybackService replays;
    private final CourseRunService courses;
    private final JsonMapper json;
    private final Clock clock;

    GhostStartStore(GhostStartRepository approvals, CourseAttemptRepository attempts,
                    RunSessionRepository sessions, DeletedRunRecordRepository deletions,
                    WithdrawnRunMemberRepository withdrawals, RunLocks locks, GhostPlaybackService replays,
                    CourseRunService courses, JsonMapper json, Clock clock) {
        this.approvals = approvals; this.attempts = attempts; this.sessions = sessions;
        this.deletions = deletions; this.withdrawals = withdrawals; this.locks = locks;
        this.replays = replays; this.courses = courses; this.json = json; this.clock = clock;
    }

    @Transactional(readOnly = true)
    public Optional<GhostStartApproval> existing(UUID owner, UUID id, GhostStart request) {
        lock(owner, id);
        return approvals.find(id).map(saved -> same(saved, request));
    }

    @Transactional(readOnly = true)
    public GhostStartApproval get(UUID owner, UUID id) {
        lock(owner, id);
        return approvals.find(id).orElseThrow(() -> new AppException(RunErrorCode.NOT_FOUND));
    }

    @Transactional
    public GhostStartApproval approve(UUID owner, UUID id, GhostStart request,
                                      CourseRouteSnapshot current, Instant validatedAt) {
        CourseAttempt attempt = lock(owner, id);
        var existing = approvals.find(id);
        if (existing.isPresent()) return same(existing.get(), request);
        // A normal course/free start cannot be retroactively converted into a ghost start.
        if (attempt.getStartedAt() != null || sessions.existsById(id)) conflict();
        if (id.equals(request.sourceRecordId()) || request.startedAt() == null
                || request.startedAt().getNano() % 1000 != 0
                || request.startedAt().isAfter(clock.instant().plusSeconds(300))
                || !"GHOST_PLAYBACK_V1".equals(request.playbackVersion()))
            throw new AppException(RunErrorCode.INVALID);

        CourseSnapshot course = new CourseSnapshot(id, attempt.getCourseId(), attempt.getCourseName(),
                List.of(json.readValue(attempt.getRouteJson(), GeoPoint[].class)),
                attempt.getTotalDistanceMeters(), attempt.getCourseVersion());
        if (!course.courseId().equals(request.courseId()) || course.version() != request.courseVersion()
                || !course.courseId().equals(current.courseId()) || course.version() != current.version()
                || course.totalDistanceMeters() != current.totalDistanceMeters()
                || !course.route().equals(current.route())) conflict();

        // Own-only playback rechecks source ownership/deletion/completion/quality under the same member lock.
        // Check ownership before taking a second session lock: cross-owner swapped IDs must not deadlock.
        sessions.findByIdAndMemberId(request.sourceRecordId(), owner)
                .orElseThrow(() -> new AppException(RunErrorCode.NOT_FOUND));
        GhostPlayback replay = replays.own(owner, request.sourceRecordId());
        if (!replay.eligible()) throw new AppException(RunErrorCode.GHOST_UNAVAILABLE);
        if (!request.playbackVersion().equals(replay.version()) || replay.course() == null
                || !course.courseId().equals(replay.course().courseId())
                || course.version() != replay.course().version()
                || course.totalDistanceMeters() != replay.course().totalDistanceMeters()
                || !course.route().equals(replay.course().route())) conflict();

        GhostStartApproval approval = new GhostStartApproval(VERSION, id, request.sourceRecordId(),
                request.startedAt(), clock.instant().truncatedTo(ChronoUnit.MICROS), validatedAt, course, replay);
        approvals.save(approval);
        // Existing F6 start: one attempt, one challenge event and one runner increment. Same transaction.
        courses.start(owner, id, request.startedAt());
        return approval;
    }

    private CourseAttempt lock(UUID owner, UUID id) {
        locks.member(owner);
        if (withdrawals.existsById(owner)) throw new AppException(RunErrorCode.NOT_FOUND);
        locks.session(id);
        if (deletions.existsById(id)) throw new AppException(RunErrorCode.NOT_FOUND);
        return attempts.findByIdAndMemberId(id, owner)
                .orElseThrow(() -> new AppException(RunErrorCode.NOT_FOUND));
    }

    private GhostStartApproval same(GhostStartApproval saved, GhostStart request) {
        if (!saved.sourceRecordId().equals(request.sourceRecordId())
                || !saved.startedAt().equals(request.startedAt())
                || !saved.course().courseId().equals(request.courseId())
                || saved.course().version() != request.courseVersion()
                || !saved.playback().version().equals(request.playbackVersion())) conflict();
        return saved;
    }

    private static void conflict() { throw new AppException(RunErrorCode.CONFLICT); }
}
