package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.response.ApiResult;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.GhostOutcome;
import io.swagger.v3.oas.annotations.Operation;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/runs/sessions/{id}/ghost/result")
class GhostResultController {
    private final GhostResultService results;
    GhostResultController(GhostResultService results) { this.results = results; }

    @Operation(summary="본인 고스트 대결의 고정 상세 비교",
        description="기존 서버 승패와 별도 저장된 대결 구간 지표·1km 및 마지막 부분 구간·누적 격차. "
            +"공개 상대 개인 센서 값은 반환하지 않는다. 구자료는 LEGACY_NO_DETAIL, 판정 전/타인/삭제는 RUN-002.")
    @GetMapping("/comparison")
    ApiResult<GhostComparison> comparison(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id) {
        UUID owner;
        try { owner=UUID.fromString(jwt.getSubject()); }
        catch(RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
        return ApiResult.success(results.comparison(owner,id));
    }

    @Operation(summary = "본인 고스트 대결의 서버 확정 결과",
            description = "저장된 요약만 반환. 승인 전·판정 전·다른 계정·삭제는 RUN-002. "
                    + "처리 대기는 기존 세션 status로 확인. 0거리 업로드의 ZERO_DISTANCE 실패에도 확정된 무효 결과는 조회 가능.")
    @GetMapping
    ApiResult<GhostOutcome> get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        UUID owner;
        try { owner = UUID.fromString(jwt.getSubject()); }
        catch (RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
        return ApiResult.success(results.get(owner, id));
    }
}
