package com.wadadak.course.internal.planner;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.stub.StubImplementation;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.Start;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import com.wadadak.course.internal.planner.PlanResult.PlanCandidate;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * 코스 자동 생성 스텁({@code app.stub.course-planner: true}). 저장하지 않고 누가 불러도 같은 값을 준다.
 * <ul>
 *     <li>plans: 선문대에서 실제 길을 따라 만든 5km 한 바퀴 후보 3개({@code planner/stub-candidates.json}, 로컬 GraphHopper로
 *     만든 값. 편의점 · 화장실 수만 스텁 값). 모양 · 거리와 상관없이 같다</li>
 *     <li>plans 상태 시험: 출발 장소 "없는 장소" PLACE_NOT_FOUND, 도착 · 경유지 "한강" PLACE_TOO_FAR, 출발 장소 "섬" NO_CANDIDATES,
 *     "중복" SIMILAR_EXISTS, "한도" COURSE-012</li>
 *     <li>parse: 선문대 출발 · 한 바퀴 · 5km · 큰길 피하기. 문장에 "초보"가 있으면 거리를 비우고, "주식"이면 무관 요청, "한도"면 COURSE-013</li>
 *     <li>quota: 20회 중 19회 남음</li>
 * </ul>
 */
@Component
@ConditionalOnProperty(name = "app.stub.course-planner", havingValue = "true")
class PlannerStub implements CoursePlanner, StubImplementation {

    private final List<PlanCandidate> candidates;

    PlannerStub(JsonMapper jsonMapper) {
        try (InputStream in = new ClassPathResource("planner/stub-candidates.json").getInputStream()) {
            candidates = jsonMapper.readValue(in, new TypeReference<>() {
            });
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @Override
    public PlanForm parse(UUID memberId, String text) {
        if (text.contains("한도")) {
            throw new AppException(CourseErrorCode.PARSE_DAILY_LIMIT_EXCEEDED);
        }
        if (text.contains("주식")) {
            return PlanForm.offTopic();
        }
        Integer distance = text.contains("초보") ? null : 5_000;
        return new PlanForm(new Start(StartKind.PLACE, "선문대"), Shape.LOOP, null, null, distance, null,
                Set.of(Pref.AVOID_ARTERIAL), null);
    }

    @Override
    public PlanResult plan(UUID memberId, PlanRequest request) {
        PlanForm form = request.form();
        String start = form.start().kind() == StartKind.PLACE ? form.start().query().strip() : null;
        String from = start != null ? start : "현재 위치";
        if ("한도".equals(start)) {
            throw new AppException(CourseErrorCode.PLAN_DAILY_LIMIT_EXCEEDED);
        }
        if ("없는 장소".equals(start)) {
            return PlanResult.placeNotFound(start, null);
        }
        if ("한강".equals(strip(form.endQuery())) || "한강".equals(strip(form.viaQuery()))) {
            return PlanResult.placeTooFar("한강", from, 80_000, start);
        }
        if ("섬".equals(start)) {
            return PlanResult.noCandidates(form.shape() == Shape.LOOP, start);
        }
        if ("중복".equals(start)) {
            return PlanResult.similarExists(start);
        }
        return PlanResult.found(candidates, start, Pref.notApplied(form.prefer(), Set.of()));
    }

    @Override
    public PlanQuota quota(UUID memberId) {
        return new PlanQuota(20, 19);
    }

    private static String strip(String s) {
        return s == null ? null : s.strip();
    }
}
