package com.wadadak.course.internal.registration;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.Difficulty;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.PrecisionModel;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;

import java.time.Instant;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseNameControllerTest {

    private static final GeometryFactory GEOMETRY = new GeometryFactory(new PrecisionModel(), 4326);

    @Autowired
    MockMvcTester mvc;

    @Autowired
    CourseRepository courseRepository;

    @BeforeEach
    void registerExistingCourse() {
        if (!courseRepository.existsActiveByName("이름확인 강변 코스")) {
            courseRepository.saveAndFlush(Course.registerCustom(UUID.randomUUID(), "이름확인 강변 코스", Difficulty.EASY, Set.of(),
                    GEOMETRY.createLineString(new Coordinate[]{new Coordinate(127.0750, 36.7990), new Coordinate(127.0750, 36.8080)}),
                    1000, "4420033000", Instant.parse("2026-11-06T14:59:59Z")));
        }
    }

    @Test
    void availableWhenNoActiveCourseHasName() {
        MvcTestResult result = check("  새로운   코스 ");

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.name").isEqualTo("새로운 코스");
        assertThat(result).bodyJson().extractingPath("$.data.available").isEqualTo(true);
    }

    @Test
    void unavailableWhenOnlySpacesOrCaseDiffer() {
        assertThat(check("이름확인강변코스")).bodyJson().extractingPath("$.data.available").isEqualTo(false);
        assertThat(check("이름 확인 강변 코스")).bodyJson().extractingPath("$.data.available").isEqualTo(false);
    }

    @Test
    void rejectsLengthOutOfRange() {
        assertThat(check(" 한 ")).hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
        assertThat(check("가".repeat(51))).hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    @Test
    void requiresLogin() {
        assertThat(mvc.get().uri("/api/v1/courses/name-availability").param("name", "새로운 코스"))
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private MvcTestResult check(String name) {
        return mvc.get().uri("/api/v1/courses/name-availability").param("name", name).with(jwt()).exchange();
    }
}
