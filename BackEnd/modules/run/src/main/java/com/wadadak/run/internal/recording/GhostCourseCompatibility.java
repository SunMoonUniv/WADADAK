package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;

/** Metadata versions may change; source reproduction and exact ordered geometry remain mandatory. */
final class GhostCourseCompatibility {
    private GhostCourseCompatibility() {}

    static GhostPlayback forCourse(CourseRouteSnapshot current, GhostPlayback replay) {
        var source = replay.course();
        if (source == null || !current.courseId().equals(source.courseId())
                || current.totalDistanceMeters() != source.totalDistanceMeters()
                || !current.route().equals(source.route()) || !source.breaks().isEmpty()
                || source.version() > current.version())
            throw new AppException(RunErrorCode.GHOST_UNAVAILABLE);
        var reference = new CourseSnapshot(source.sessionId(), source.courseId(), source.name(), source.route(),
                source.totalDistanceMeters(), current.version(), source.breaks());
        return new GhostPlayback(replay.sourceRecordId(), reference, replay.version(), replay.sourcePolicyVersion(),
                replay.sourceCalculationVersion(), replay.courseElapsedSeconds(), replay.durationMs(), replay.eligible(),
                replay.unavailableReasons(), replay.quality(), replay.samples(), replay.spans());
    }
}
