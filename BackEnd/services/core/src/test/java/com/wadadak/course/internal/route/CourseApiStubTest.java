package com.wadadak.course.internal.route;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.CourseRouteSnapshot;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 스텁을 켰을 때({@code app.stub.course: true}) 실제 구현 대신 스텁이 뜨고 계약대로 동작하는지.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
@TestPropertySource(properties = "app.stub.course=true")
class CourseApiStubTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    CourseApi courseApi;

    @Test
    void stubIsUsedWhenEnabled() {
        assertThat(courseApi).isInstanceOf(CourseApiStub.class);
    }

    @Test
    void returnsFixedRouteForAnyId() {
        UUID courseId = UUID.randomUUID();

        CourseRouteSnapshot snapshot = courseApi.getRouteForRun(courseId);

        assertThat(snapshot.courseId()).isEqualTo(courseId);
        assertThat(snapshot.route()).hasSizeGreaterThanOrEqualTo(2);
        assertThat(snapshot.totalDistanceMeters()).isGreaterThanOrEqualTo(1000);
    }

    @Test
    void throwsForErrorIds() {
        assertThatThrownBy(() -> courseApi.getRouteForRun(CourseApiStub.NOT_FOUND_ID))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CourseErrorCode.COURSE_NOT_FOUND));
        assertThatThrownBy(() -> courseApi.getRouteForRun(CourseApiStub.NOT_AVAILABLE_ID))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(CourseErrorCode.COURSE_NOT_AVAILABLE));
    }
}
