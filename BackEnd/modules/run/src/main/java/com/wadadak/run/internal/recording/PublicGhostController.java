package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.response.ApiResult;
import com.wadadak.ranking.RankingPeriod;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.PublicGhostPreparation;
import io.swagger.v3.oas.annotations.Operation;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/runs/records")
class PublicGhostController {
    private final PublicGhostService ghosts;
    PublicGhostController(PublicGhostService ghosts){this.ghosts=ghosts;}
    @Operation(summary="공개 코스 고스트 재생 준비",
        description="선택 기간의 공개 대표 완주 기록을 재검증하고 코스 기준 경로와 파생 위치/시간 자료만 제공한다. "
            +"본인·삭제·비공개 원본은 허용하지 않는다. 이 조회는 측정이나 코스 도전을 시작하지 않는다.")
    @GetMapping("/{id}/public-ghost-playback")
    ApiResult<PublicGhostPreparation> playback(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id,
        @RequestParam UUID courseId,@RequestParam(defaultValue="ALL") RankingPeriod period){
        UUID owner;
        try{owner=UUID.fromString(jwt.getSubject());}
        catch(RuntimeException e){throw new AppException(RunErrorCode.INVALID);}
        return ApiResult.success(ghosts.prepare(owner,courseId,period,id));
    }
}
