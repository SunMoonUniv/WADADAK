package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.response.ApiResult;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.CoursePrepare;
import com.wadadak.run.internal.RunContracts.CourseSnapshot;
import com.wadadak.run.internal.RunContracts.CourseStart;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/** 코스 러닝 시작 전후의 서버 연결(정책 D-08). 러닝 중에는 이 두 신호 말고 통신하지 않는다 */
@RestController
@RequestMapping("/api/v1/runs/sessions/{id}/course")
class CourseRunController {

    private final CourseRunService courseRuns;

    CourseRunController(CourseRunService courseRuns) {
        this.courseRuns = courseRuns;
    }

    @Operation(summary = "코스 러닝 준비",
            description = "C6에서 측정 시작 전에 부른다. 코스가 공개 중인지 확인하고 판정용 경로를 저장해 돌려준다. "
                    + "같은 세션·코스 재시도는 처음 경로를 그대로 준다. 실패하면 앱은 시작하지 않는다(D-08)")
    @PutMapping
    ApiResult<CourseSnapshot> prepare(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id,
                                      @Valid @RequestBody CoursePrepare body) {
        return ApiResult.success(courseRuns.prepare(owner(jwt), id, body.courseId()));
    }

    @Operation(summary = "코스 러닝 시작 신호",
            description = "카운트다운이 끝나 측정을 시작할 때 부른다. 도전 수와 현재 러너 수에 반영한다. "
                    + "같은 startedAt 재시도는 한 번만 반영한다. 실패하면 앱은 시작하지 않는다(D-08)")
    @PostMapping("/start")
    ApiResult<Void> start(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id, @Valid @RequestBody CourseStart body) {
        courseRuns.start(owner(jwt), id, body.startedAt());
        return ApiResult.success();
    }

    @Operation(summary = "코스 구간 종료 신호",
            description = "경로 끝 도착·코스만 종료 때 온라인이면 부른다. 현재 러너 수에서 뺀다. "
                    + "판정에는 쓰지 않는다(판정 경계는 기록의 SEGMENT_END). 자유 러닝·이미 끝난 세션이면 무시한다")
    @PostMapping("/segment-end")
    ApiResult<Void> segmentEnd(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        courseRuns.segmentEnd(owner(jwt), id);
        return ApiResult.success();
    }

    private static UUID owner(Jwt jwt) {
        try {
            return UUID.fromString(jwt.getSubject());
        } catch (RuntimeException e) {
            throw new AppException(RunErrorCode.INVALID);
        }
    }
}
