package com.wadadak.course.internal.course;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.event.course.CourseStatus;
import org.junit.jupiter.api.Test;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.LineString;
import org.locationtech.jts.geom.PrecisionModel;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;

import java.time.Instant;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseRepositoryTest {

    private static final GeometryFactory GEOMETRY = new GeometryFactory(new PrecisionModel(), 4326);

    @Autowired
    CourseRepository courseRepository;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void savesAndLoadsCustomCourse() {
        Course saved = courseRepository.saveAndFlush(course("저장 확인 코스", Set.of(CourseTag.RIVERSIDE, CourseTag.FLAT)));

        Course loaded = courseRepository.findById(saved.getId()).orElseThrow();
        assertThat(loaded.getCourseType()).isEqualTo(CourseType.CUSTOM);
        assertThat(loaded.getTags()).containsExactlyInAnyOrder(CourseTag.RIVERSIDE, CourseTag.FLAT);
        assertThat(loaded.getRoute().getNumPoints()).isEqualTo(3);
        // x = 경도, y = 위도. 첫 점이 출발점이다
        assertThat(loaded.getStartPoint().getX()).isEqualTo(127.0750);
        assertThat(loaded.getStartPoint().getY()).isEqualTo(36.7990);
        assertThat(loaded.getEmdCode()).isEqualTo("4420033000");
        assertThat(loaded.getSigunguCode()).isEqualTo("4420000000");
        assertThat(loaded.getSidoCode()).isEqualTo("4400000000");
        assertThat(loaded.getStatus()).isEqualTo(CourseStatus.ACTIVE);
        assertThat(loaded.getVersion()).isZero();
    }

    @Test
    void savesCourseWithoutTags() {
        Course saved = courseRepository.saveAndFlush(course("태그 없는 코스", Set.of()));

        assertThat(courseRepository.findById(saved.getId()).orElseThrow().getTags()).isEmpty();
    }

    @Test
    void rejectsSameActiveNameIgnoringCase() {
        courseRepository.saveAndFlush(course("River Run", Set.of()));

        assertThat(courseRepository.existsActiveByName("river run")).isTrue();
        assertThatThrownBy(() -> courseRepository.saveAndFlush(course("RIVER RUN", Set.of())))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void allowsNameOfHiddenCourse() {
        Course hidden = courseRepository.saveAndFlush(course("숨긴 코스 이름", Set.of()));
        jdbcTemplate.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'EXPIRED', hidden_at = now() WHERE id = ?",
                hidden.getId());

        assertThat(courseRepository.existsActiveByName("숨긴 코스 이름")).isFalse();
        courseRepository.saveAndFlush(course("숨긴 코스 이름", Set.of()));
    }

    private static Course course(String name, Set<CourseTag> tags) {
        LineString route = GEOMETRY.createLineString(new Coordinate[]{
                new Coordinate(127.0750, 36.7990),
                new Coordinate(127.0750, 36.8035),
                new Coordinate(127.0750, 36.8080)});
        return Course.registerCustom(UUID.randomUUID(), name, Difficulty.EASY, tags, route, 1001, "4420033000",
                Instant.parse("2026-11-06T14:59:59Z"));
    }
}
