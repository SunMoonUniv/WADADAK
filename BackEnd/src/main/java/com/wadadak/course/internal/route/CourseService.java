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
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * {@link CourseApi} 실제 구현. {@code app.stub.course: true}면 {@link CourseApiStub}이 대신 뜬다(개발 정책 3장).
 */
@Service
@ConditionalOnProperty(name = "app.stub.course", havingValue = "false", matchIfMissing = true)
@RequiredArgsConstructor
class CourseService implements CourseApi {

    private final CourseRepository courseRepository;
    private final JdbcClient jdbc;

    @Override
    @Transactional(readOnly = true)
    public CourseRouteSnapshot getRouteForRun(UUID courseId) {
        Course course = courseRepository.findById(courseId)
                .orElseThrow(() -> new AppException(CourseErrorCode.COURSE_NOT_FOUND));
        if (!course.isActive()) {
            throw new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE);
        }
        return new CourseRouteSnapshot(course.getId(), course.getName(), CourseGeometry.points(course.getRoute()),
                course.getDistanceMeters(), course.getVersion(), hasElevationProfile(courseId));
    }

    /**
     * 고도 프로필이 이미 있나(코스 상세 B1-03과 같다). 등록 기록으로 만든 GPS 코스 프로필(고도 부족 JSON {@code null} · 아직 안 만든
     * SQL NULL은 없음)이나 완주로 만든 프로필이 있으면 true다. true면 run은 완주 경로(CourseRunTrackEvent)를 보내지 않는다.
     */
    private boolean hasElevationProfile(UUID courseId) {
        return jdbc.sql("""
                        SELECT EXISTS (SELECT 1 FROM course.gps_course_sources
                                       WHERE course_id = :courseId AND elevation_profile_json <> 'null')
                            OR EXISTS (SELECT 1 FROM course.completion_elevation_profiles WHERE course_id = :courseId)""")
                .param("courseId", courseId)
                .query(Boolean.class)
                .single();
    }

    @Override
    @Transactional(readOnly = true)
    public Map<UUID, String> getNames(Set<UUID> courseIds) {
        if (courseIds.isEmpty()) {
            return Map.of(); // 빈 IN ()은 SQL 문법 오류다
        }
        return jdbc.sql("SELECT id, name FROM course.courses WHERE id IN (:ids)")
                .param("ids", courseIds)
                .query((rs, rowNum) -> Map.entry(rs.getObject("id", UUID.class), rs.getString("name")))
                .list().stream()
                .collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }

    @Override
    public GpsGapCheck checkGpsGaps(List<List<GeoPoint>> segments) {
        return new GpsGapCheck(GpsGapRule.passes(segments), GpsGapRule.VERSION);
    }
}
