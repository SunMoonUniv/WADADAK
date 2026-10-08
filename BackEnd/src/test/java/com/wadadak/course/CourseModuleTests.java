package com.wadadak.course;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * course 단독 기동(다른 도메인 모듈 없이). 분리 가능성의 직접 증거다(개발 정책 10.6).
 * 실제 구현 전이라 {@code app.stub.course: true}로 스텁이 뜬다.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseModuleTests {

    @Autowired
    CourseApi courseApi;

    @Test
    void returnsRouteSnapshotFromStub() {
        UUID courseId = UUID.randomUUID();

        CourseRouteSnapshot snapshot = courseApi.getRouteForRun(courseId);

        assertThat(snapshot.courseId()).isEqualTo(courseId);
        assertThat(snapshot.route()).hasSizeGreaterThanOrEqualTo(2);
        assertThat(snapshot.totalDistanceMeters()).isGreaterThanOrEqualTo(1000);
    }

    @Test
    void stubThrowsForErrorIds() {
        assertThatThrownBy(() -> courseApi.getRouteForRun(UUID.fromString("00000000-0000-0000-0000-000000000001")))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CourseErrorCode.COURSE_NOT_FOUND));
        assertThatThrownBy(() -> courseApi.getRouteForRun(UUID.fromString("00000000-0000-0000-0000-000000000002")))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CourseErrorCode.COURSE_NOT_AVAILABLE));
    }
}
