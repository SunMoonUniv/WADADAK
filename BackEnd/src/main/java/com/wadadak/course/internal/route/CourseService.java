package com.wadadak.course.internal.route;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.course.GpsGapCheck;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.registration.GpsGapRule;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * {@link CourseApi} 실제 구현. {@code app.stub.course: true}면 {@link CourseApiStub}이 대신 뜬다(개발 정책 3장).
 */
@Service
@ConditionalOnProperty(name = "app.stub.course", havingValue = "false", matchIfMissing = true)
@RequiredArgsConstructor
class CourseService implements CourseApi {

    private final CourseRepository courseRepository;

    @Override
    @Transactional(readOnly = true)
    public CourseRouteSnapshot getRouteForRun(UUID courseId) {
        Course course = courseRepository.findById(courseId)
                .orElseThrow(() -> new AppException(CourseErrorCode.COURSE_NOT_FOUND));
        if (!course.isActive()) {
            throw new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE);
        }
        return new CourseRouteSnapshot(course.getId(), course.getName(), CourseGeometry.points(course.getRoute()),
                course.getDistanceMeters(), course.getVersion());
    }

    @Override
    public GpsGapCheck checkGpsGaps(List<List<GeoPoint>> segments) {
        return new GpsGapCheck(GpsGapRule.passes(segments), GpsGapRule.VERSION);
    }
}
