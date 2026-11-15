package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.response.ApiResult;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.paging.CursorSlice;
import org.springdoc.core.annotations.ParameterObject;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.RunErrorCode;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/runs")
class RunController {
    private final RunService runs;
    RunController(RunService runs) { this.runs=runs; }
    @PutMapping("/sessions/{id}") ApiResult<Status> prepare(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id,@Valid @RequestBody Prepare body) {
        return ApiResult.success(runs.prepare(owner(jwt),id,body));
    }
    @PostMapping("/sessions/{id}/record") ApiResult<Status> upload(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id,@Valid @RequestBody Upload body) {
        return ApiResult.success(runs.upload(owner(jwt),id,body));
    }
    @GetMapping("/sessions/{id}/status") ApiResult<Status> status(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id) {
        return ApiResult.success(runs.status(owner(jwt),id));
    }
    @GetMapping("/records") ApiResult<CursorSlice<RecordSummary>> history(@AuthenticationPrincipal Jwt jwt,@ParameterObject @Valid Cursorable page) {
        return ApiResult.success(runs.history(owner(jwt),page));
    }
    @GetMapping("/records/{id}") ApiResult<Result> result(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id) {
        return ApiResult.success(runs.result(owner(jwt),id));
    }
    /** GPS 코스 등록(F7 B6·D4)용 원본 경로. 결과 화면 지도와 같은 구간(끊긴 곳은 나눔)과 지점별 GPS 정확도·고도 */
    @GetMapping("/records/{id}/course-source") ApiResult<CourseSource> courseSource(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id) {
        return ApiResult.success(runs.courseSource(owner(jwt),id));
    }
    /** 구간 분석(D3·D5·D6): 결과 랩마다 케이던스·고도 변화·누적 상승 */
    @GetMapping("/records/{id}/splits") ApiResult<Splits> splits(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id) {
        return ApiResult.success(runs.splits(owner(jwt),id));
    }
    @DeleteMapping("/records/{id}") ApiResult<Deleted> delete(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id) {
        return ApiResult.success(runs.delete(owner(jwt),id));
    }
    private UUID owner(Jwt jwt) {
        try { return UUID.fromString(jwt.getSubject()); }
        catch(RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
    }
}
