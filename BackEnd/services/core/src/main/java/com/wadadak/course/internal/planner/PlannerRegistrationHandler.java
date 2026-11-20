package com.wadadak.course.internal.planner;

import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.planner.PlannerLogRepository.RecentPlan;
import com.wadadak.course.internal.registration.SimilarityChecker;
import com.wadadak.event.course.CourseCreatedEvent;
import lombok.RequiredArgsConstructor;
import org.locationtech.jts.geom.LineString;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * 분석 로그에 "실제로 등록했는지"를 남긴다(논문용). 코스 찾기만 하고 버린 것과, 후보로 코스를 만든 것을 가른다.
 *
 * <p>앱은 등록할 때 어느 후보였는지 보내지 않는다. 그래서 코스가 등록되면 같은 사람이 {@value PlannerLogRepository#REGISTER_WINDOW}
 * 안에 한 코스 찾기의 후보와 등록 경로를 비교해, 85% 이상 겹치는 후보(코스 유사도와 같은 계산)를 찾는다.
 * 사용자가 후보를 고른 뒤 점을 조금 옮겨도 같은 후보로 잡히고, 많이 고치면 등록 표시가 남지 않는다.
 *
 * <p>[@ApplicationModuleListener] 등록 트랜잭션이 끝난 뒤 따로 돈다. 그래서 여기서 실패해도 등록은 그대로 성공이고,
 * 이벤트 발행 기록이 남아 나중에 다시 시도된다(같은 찾기를 두 번 표시하지 않는다).
 */
@Component
@RequiredArgsConstructor
class PlannerRegistrationHandler {

    private final PlannerLogRepository logs;
    private final CourseRepository courses;
    private final SimilarityChecker similarity;

    @ApplicationModuleListener
    public void on(CourseCreatedEvent event) {
        // GPS 주행 등록(러닝 기록으로 만든 코스)은 자동 생성과 상관없다
        if (event.sourceRunRecordId() == null) {
            link(event.courseId(), event.creatorId());
        }
    }

    /** 최근 찾기부터 후보를 1위부터 보며 처음 맞는 하나에 표시한다 */
    void link(UUID courseId, UUID memberId) {
        LineString route = courses.findById(courseId).map(Course::getRoute).orElse(null);
        if (route == null) {
            return;
        }
        for (RecentPlan plan : logs.recentUnregistered(memberId)) {
            for (int i = 0; i < plan.candidates().size(); i++) {
                LineString candidate = CourseGeometry.lineString(plan.candidates().get(i));
                // 어느 쪽 길이로 재도 85% 이상이면 같은 길(CandidateSelector의 후보끼리 겹침과 같다)
                if (similarity.similarity(route, candidate) >= SimilarityChecker.MAX_SIMILARITY
                        || similarity.similarity(candidate, route) >= SimilarityChecker.MAX_SIMILARITY) {
                    logs.markRegistered(plan.id(), courseId, i + 1);
                    return;
                }
            }
        }
    }
}
