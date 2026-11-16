package com.wadadak.run.internal.recording;

import com.wadadak.common.response.ApiResult;
import com.wadadak.run.internal.RunContracts.*;
import io.swagger.v3.oas.annotations.Operation;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/runs")
class FreeGhostController {
    private final FreeGhostService ghosts;
    FreeGhostController(FreeGhostService ghosts) { this.ghosts=ghosts; }
    @Operation(summary="내 자유 러닝 고스트 후보",description="코스 등록 없이 실제 시작 시각순 조회. 1km 미만도 비활성 사유 표시용으로 반환. 원본 적합성은 선택 준비와 시작 때 검증.")
    @GetMapping("/ghost-candidates/own/free")
    ApiResult<FreeGhostPage> candidates(@AuthenticationPrincipal Jwt jwt,
        @RequestParam(defaultValue="ALL") OwnGhostPeriod period,@RequestParam(defaultValue="20") int size,
        @RequestParam(required=false) String cursor) {
        return ApiResult.success(ghosts.candidates(owner(jwt),period,size,cursor));
    }
    @Operation(summary="내 자유 기록 고스트 준비",description="1,000m 이상·중단 원본 허용. 저장된 경로 조각과 동일 완주 기준의 비교 시간·원본 시간·공백 품질을 제공. 원본 수정·코스 등록 없음.")
    @GetMapping("/records/{id}/free-ghost-playback")
    ApiResult<FreeGhostPreparation> prepare(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id,
        @RequestParam(defaultValue="GHOST_PLAYBACK_FREE_V1") String playbackVersion) {
        return ApiResult.success(ghosts.prepare(owner(jwt),id,playbackVersion));
    }
    private static UUID owner(Jwt jwt) {
        try {return UUID.fromString(jwt.getSubject());}
        catch(RuntimeException e){throw new com.wadadak.common.exception.AppException(com.wadadak.run.RunErrorCode.INVALID);}
    }
}
