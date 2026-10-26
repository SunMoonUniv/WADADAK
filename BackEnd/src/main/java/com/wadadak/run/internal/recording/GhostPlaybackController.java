package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.response.ApiResult;
import com.wadadak.run.RunErrorCode;
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
    GhostPlaybackController(GhostPlaybackService playback) { this.playback = playback; }

    @Operation(summary = "내 완주 기록 고스트 재생 자료",
            description = "본인 기록만 조회. 총 소요 ms의 위치·정지·공백과 30초/5% 적합성. "
                    + "재생 불가는 eligible=false와 사유를 반환하며 기존 결과·랭킹을 변경하지 않습니다.")
    @GetMapping("/{id}/ghost-playback")
    ApiResult<GhostPlayback> own(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        UUID owner;
        try { owner = UUID.fromString(jwt.getSubject()); }
        catch (RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
        return ApiResult.success(playback.own(owner, id));
    }
}
