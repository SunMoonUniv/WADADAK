package com.wadadak.course;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.Difficulty;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;

import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * course 단독 기동(다른 도메인 모듈 없이). 분리 가능성의 직접 증거다(개발 정책 10.6).
 * {@code app.stub.course: false}라 {@link CourseApi} 실제 구현이 뜬다. 스텁은 {@code CourseApiStubTest}.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseModuleTests {

    // 출발 → 북쪽 → 동쪽. 좌표 순서가 코스 방향이다
    private static final List<GeoPoint> ROUTE = List.of(
            new GeoPoint(37.5000, 127.1000), new GeoPoint(37.5090, 127.1000), new GeoPoint(37.5090, 127.1050));

    @Autowired
    CourseApi courseApi;

    @Autowired
    CourseRepository courseRepository;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void returnsRouteSnapshotInCourseDirection() {
        Course course = save("러닝 시작용 코스");

        CourseRouteSnapshot snapshot = courseApi.getRouteForRun(course.getId());

        assertThat(snapshot.courseId()).isEqualTo(course.getId());
        assertThat(snapshot.name()).isEqualTo("러닝 시작용 코스");
        assertThat(snapshot.route()).containsExactlyElementsOf(ROUTE);
        assertThat(snapshot.totalDistanceMeters()).isEqualTo(1441);
        assertThat(snapshot.version()).isZero();
    }

    @Test
    void throwsNotFoundForUnknownCourse() {
        assertThatThrownBy(() -> courseApi.getRouteForRun(UUID.randomUUID()))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CourseErrorCode.COURSE_NOT_FOUND));
    }

    @Test
    void throwsNotAvailableForHiddenOrDeletedCourse() {
        Course hidden = save("숨긴 러닝 코스");
        Course deleted = save("삭제된 러닝 코스");
        jdbcTemplate.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'EXPIRED', hidden_at = now() WHERE id = ?",
                hidden.getId());
        jdbcTemplate.update("UPDATE course.courses SET status = 'DELETED', status_reason = 'USER_DELETED', hidden_at = now() WHERE id = ?",
                deleted.getId());

        for (UUID id : List.of(hidden.getId(), deleted.getId())) {
            assertThatThrownBy(() -> courseApi.getRouteForRun(id))
                    .isInstanceOfSatisfying(AppException.class,
                            e -> assertThat(e.getErrorCode()).isEqualTo(CourseErrorCode.COURSE_NOT_AVAILABLE));
        }
    }

    private Course save(String name) {
        return courseRepository.saveAndFlush(Course.registerCustom(UUID.randomUUID(), name, Difficulty.MEDIUM, Set.of(),
                CourseGeometry.lineString(ROUTE), 1441, "1171010100", Instant.parse("2026-11-06T14:59:59Z")));
    }
}
