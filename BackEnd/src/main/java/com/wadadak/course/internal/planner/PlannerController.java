package com.wadadak.course.internal.planner;

import com.wadadak.common.response.ApiResult;
import com.wadadak.course.internal.planner.CoursePlanner.ParseRequest;
import com.wadadak.course.internal.planner.CoursePlanner.PlanQuota;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/** B3 `자동 생성`(정책 B3-A01~A08). 실제 구현 전이라 {@code app.stub.course-planner: true}일 때만 뜬다(개발 정책 3.2). */
@RestController
@RequestMapping("/api/v1/courses/plans")
@ConditionalOnProperty(name = "app.stub.course-planner", havingValue = "true")
@RequiredArgsConstructor
class PlannerController {

    private final CoursePlanner planner;

    @Operation(summary = "문장으로 조건 채우기 (A1 `조건 자동 채우기`)",
            description = "문장(1~200자)을 폼으로 바꾼다. 읽지 못한 거리 · 시간은 null, 출발 · 모양은 현재 위치 · 한 바퀴로 채운다. "
                    + "코스와 무관한 문장이면 message만 채운다. 앱은 결과를 A7-1 폼에 넣고 사용자가 확인한 뒤 plans를 부른다. "
                    + "문장은 외부 판단 모델로 간다(정책 B3-A06). 하루 50회 초과 COURSE-013, 빈 문장 · 200자 초과 COMMON-001.")
    @PostMapping("/parse")
    ApiResult<PlanForm> parse(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody ParseRequest request) {
        return ApiResult.success(planner.parse(memberId(jwt), request.text()));
    }

    @Operation(summary = "코스 후보 만들기 (A7 `코스 찾기`)",
            description = "길을 따라가는 후보를 최대 3개 준다. 고른 후보의 anchorPoints로 B3 입력점을 채운다. "
                    + "후보가 없으면 reason과 message: PLACE_NOT_FOUND · PLACE_TOO_FAR는 폼에, NO_CANDIDATES · SIMILAR_EXISTS는 A6에 보인다. "
                    + "편도는 endQuery, 경유는 viaQuery, 한 바퀴 · 왕복은 거리나 시간이 필요하다. "
                    + "목표 거리(시간은 paceSecPerKm, 없으면 390초/km로 환산)는 1~100km, 한 바퀴는 22km까지. 어긋나면 COMMON-001. "
                    + "하루 20회 초과 COURSE-012(장소를 못 찾았거나 길을 찾지 않은 요청은 세지 않는다).")
    @PostMapping
    ApiResult<PlanResult> plan(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody PlanRequest request) {
        return ApiResult.success(planner.plan(memberId(jwt), request));
    }

    @Operation(summary = "오늘 남은 코스 자동 생성 횟수 (A1 · A8)", description = "하루 20회, Asia/Seoul 00:00에 초기화한다.")
    @GetMapping("/quota")
    ApiResult<PlanQuota> quota(@AuthenticationPrincipal Jwt jwt) {
        return ApiResult.success(planner.quota(memberId(jwt)));
    }

    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
