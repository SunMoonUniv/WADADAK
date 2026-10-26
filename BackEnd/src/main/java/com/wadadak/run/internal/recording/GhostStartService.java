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

    GhostStartService(GhostStartStore store, CourseApi courses, Clock clock) {
        this.store = store; this.courses = courses; this.clock = clock;
    }

    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    public GhostStartApproval start(UUID owner, UUID id, GhostStart request) {
        var saved = store.existing(owner, id, request);
        if (saved.isPresent()) return saved.get(); // No dependency on the original record/current course on retry.
        CourseRouteSnapshot current;
        try {
            current = courses.getRouteForRun(request.courseId());
        } catch (RuntimeException failure) {
            // A concurrent identical request may have committed while this course read failed.
            var committed = store.existing(owner, id, request);
            if (committed.isPresent()) return committed.get();
            throw failure;
        }
        return store.approve(owner, id, request, current, clock.instant().truncatedTo(ChronoUnit.MICROS));
    }
}
