package com.wadadak.course.internal.route;

import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.stub.StubImplementation;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseRouteSnapshot;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;

/**
 * 어떤 ID든 선문대 아산캠퍼스에서 북쪽으로 곧게 뻗은 약 1km 코스를 돌려준다.
 */
@Component
@ConditionalOnProperty(name = "app.stub.course", havingValue = "true")
class CourseApiStub implements CourseApi, StubImplementation {

    private static final List<GeoPoint> ROUTE = List.of(
            new GeoPoint(36.7990, 127.0750),
            new GeoPoint(36.8035, 127.0750),
            new GeoPoint(36.8080, 127.0750));

    @Override
    public CourseRouteSnapshot getRouteForRun(UUID courseId) {
        return new CourseRouteSnapshot(courseId, "스텁 코스-" + courseId.toString().substring(0, 4), ROUTE, 1001, 0);
    }
}
