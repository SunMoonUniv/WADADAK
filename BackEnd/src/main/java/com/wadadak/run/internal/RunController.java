package com.wadadak.run.internal;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.response.ApiResult;
import com.wadadak.run.RunContracts.*;
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
    @GetMapping("/records") ApiResult<Page> history(@AuthenticationPrincipal Jwt jwt,@RequestParam(required=false) String cursor) {
        return ApiResult.success(runs.history(owner(jwt),cursor));
    }
    @GetMapping("/records/{id}") ApiResult<Result> result(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id) {
        return ApiResult.success(runs.result(owner(jwt),id));
    }
    @DeleteMapping("/records/{id}") ApiResult<Deleted> delete(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id) {
        return ApiResult.success(runs.delete(owner(jwt),id));
    }
    private UUID owner(Jwt jwt) {
        try { return UUID.fromString(jwt.getSubject()); }
        catch(RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
    }
}
