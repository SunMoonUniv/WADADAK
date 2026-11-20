package com.wadadak.course.internal.planner;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.Start;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import com.wadadak.course.internal.planner.PlanResult.PlanCandidate;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static com.wadadak.course.internal.planner.CandidateGenerator.destination;
import static org.assertj.core.api.Assertions.assertThat;

/** 코스를 등록하면 그 코스를 만든 후보에 "등록함"을 표시한다. 이벤트 대신 link를 바로 불러 본다(이벤트는 등록 뒤 따로 돈다) */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class PlannerRegistrationHandlerTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    PlannerRegistrationHandler handler;

    @Autowired
    PlannerLogRepository logs;

    @Autowired
    CourseRepository courses;

    @Autowired
    JdbcTemplate jdbcTemplate;

    /** 다른 테스트의 코스와 겹치지 않는 바다 위 */
    private static final GeoPoint BASE = new GeoPoint(34.10, 125.40);

    @Test
    void marksTheCandidateTheCourseWasMadeFrom() {
        UUID member = UUID.randomUUID();
        List<GeoPoint> first = square(BASE);
        List<GeoPoint> second = square(destination(BASE, 3_000, 90));
        UUID plan = plan(member, first, second);
        // 2위 후보를 골라 한 점을 5m 옮겨 등록했다(85% 이상 같은 길)
        List<GeoPoint> edited = new java.util.ArrayList<>(second);
        edited.set(2, destination(second.get(2), 5, 0));
        UUID course = course(member, edited);

        handler.link(course, member);

        Map<String, Object> row = jdbcTemplate.queryForMap(
                "SELECT registered_course_id, registered_rank, registered_at FROM course.planner_plan_logs WHERE id = ?", plan);
        assertThat(row.get("registered_course_id")).isEqualTo(course);
        assertThat(row.get("registered_rank")).isEqualTo(2);
        assertThat(row.get("registered_at")).isNotNull();

        // 같은 이벤트를 다시 받아도 그대로다
        handler.link(course(member, first), member);
        assertThat(jdbcTemplate.queryForObject("SELECT registered_rank FROM course.planner_plan_logs WHERE id = ?", Integer.class, plan))
                .isEqualTo(2);
    }

    @Test
    void ignoresOtherPeopleAndDifferentRoutesAndOldSearches() {
        UUID member = UUID.randomUUID();
        GeoPoint base = destination(BASE, 10_000, 180);
        List<GeoPoint> candidate = square(base);
        UUID otherPersons = plan(UUID.randomUUID(), candidate);
        UUID old = plan(member, candidate);
        jdbcTemplate.update("UPDATE course.planner_plan_logs SET created_at = now() - interval '2 hours' WHERE id = ?", old);
        UUID recent = plan(member, candidate);

        // 후보와 다른 길을 등록했다
        handler.link(course(member, square(destination(base, 3_000, 90))), member);
        assertThat(registered(recent)).isNull();

        // 같은 길이면 이 사람의 1시간 안 찾기만
        handler.link(course(member, candidate), member);
        assertThat(registered(recent)).isEqualTo(1);
        assertThat(registered(otherPersons)).isNull();
        assertThat(registered(old)).isNull();
    }

    private Integer registered(UUID plan) {
        return jdbcTemplate.queryForObject("SELECT registered_rank FROM course.planner_plan_logs WHERE id = ?", Integer.class, plan);
    }

    /** 이 사람의 코스 찾기 로그 하나(후보는 순위순). 로그 id */
    @SafeVarargs
    private UUID plan(UUID member, List<GeoPoint>... candidates) {
        PlanForm form = new PlanForm(new Start(StartKind.CURRENT, null), Shape.LOOP, null, null, 4_000, null, Set.of(), null);
        List<PlanCandidate> sent = java.util.Arrays.stream(candidates)
                .map(points -> new PlanCandidate(points, 4_000, 0, 0, 0, 0, null, null, null, null)).toList();
        logs.savePlan(member, new PlanRequest(form, BASE, null), PlanResult.found(sent, null, Set.of()), 10, 100L, 10L);
        return jdbcTemplate.queryForObject("SELECT id FROM course.planner_plan_logs ORDER BY created_at DESC, id DESC LIMIT 1", UUID.class);
    }

    private UUID course(UUID member, List<GeoPoint> route) {
        return courses.saveAndFlush(Course.registerCustom(member, "자동 " + UUID.randomUUID().toString().substring(0, 8),
                Difficulty.MEDIUM, Set.of(), CourseGeometry.lineString(route), 4_000, "4420033000",
                Instant.parse("2027-11-10T14:59:59Z"))).getId();
    }

    /** 한 변 1km 정사각형 한 바퀴 */
    private static List<GeoPoint> square(GeoPoint start) {
        GeoPoint east = destination(start, 1_000, 90);
        GeoPoint northEast = destination(east, 1_000, 0);
        GeoPoint north = destination(start, 1_000, 0);
        return List.of(start, east, northEast, north, start);
    }
}
