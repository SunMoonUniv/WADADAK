package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.response.ApiResult;
import com.wadadak.run.RunErrorCode;
import com.wadadak.course.CourseApi;
import com.wadadak.run.internal.RunContracts.GhostPlayback;
import io.swagger.v3.oas.annotations.Operation;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/runs/records")
class GhostPlaybackController {
    private final GhostPlaybackService playback;
    private final CourseApi courses;
    GhostPlaybackController(GhostPlaybackService playback, CourseApi courses) { this.playback = playback; this.courses=courses; }

    @Operation(summary = "내 완주 기록 고스트 재생 자료",
            description = "본인 기록만 조회. 총 소요 ms의 위치·정지·공백과 30초/5% 적합성. "
                    + "courseId/courseVersion을 함께 주면 현재 코스와 ID·순서 있는 경로·거리가 같은 원본만 현재 준비 버전으로 제공합니다. "
                    + "둘 다 생략하면 원본 버전을 유지합니다. 재생 불가는 eligible=false와 사유를 반환하며 기존 결과·랭킹을 변경하지 않습니다.")
    @GetMapping("/{id}/ghost-playback")
    ApiResult<GhostPlayback> own(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id,
            @RequestParam(required=false) UUID courseId, @RequestParam(required=false) Long courseVersion) {
        UUID owner;
        try { owner = UUID.fromString(jwt.getSubject()); }
        catch (RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
        if ((courseId==null)!=(courseVersion==null) || courseVersion!=null && courseVersion<0)
            throw new AppException(RunErrorCode.INVALID);
        var replay=playback.own(owner,id); // Source ownership and original-version reproduction remain mandatory.
        if(courseId!=null) {
            var current=courses.getRouteForRun(courseId); // Outside the source transaction; no write transaction here.
            if(current.version()!=courseVersion) throw new AppException(RunErrorCode.CONFLICT);
            if(replay.eligible()) replay=GhostCourseCompatibility.forCourse(current,replay);
        }
        return ApiResult.success(replay);
    }
}
