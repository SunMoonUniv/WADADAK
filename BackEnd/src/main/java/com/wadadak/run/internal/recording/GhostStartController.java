package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.response.ApiResult;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/runs/sessions/{id}/ghost")
class GhostStartController {
    private final GhostStartService starts;
    private final GhostStartStore store;
    private final FreeGhostService freeGhosts;

    GhostStartController(GhostStartService starts, GhostStartStore store, FreeGhostService freeGhosts) {
        this.starts = starts; this.store = store; this.freeGhosts=freeGhosts;
    }

    @Operation(summary = "내 고스트 대결 시작 승인·상대 고정",
            description = "기존 course 준비 후 호출. 코스 활성·경로 버전과 본인 완주 재생 적합성을 재검증하고 상대를 저장한다. "
                    + "기존 코스 시작 신호도 같은 트랜잭션에서 처리하므로 course/start를 별도로 보낼 필요 없다. "
                    + "동일 세션·모든 요청 필드가 같은 재시도는 최초 승인/재생 자료를 반환한다. "
                    + "startedAt은 마이크로초 정밀도까지 허용. RUN-004는 상대 재선택, RUN-003은 충돌이다.")
    @PostMapping("/start")
    ApiResult<GhostStartApproval> start(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id,
                                       @Valid @RequestBody GhostStart request) {
        return ApiResult.success(starts.start(owner(jwt), id, request));
    }

    @Operation(summary = "저장된 고스트 시작 승인 재확인",
            description = "시작 응답 유실 시 같은 세션 ID로 조회한다. 원본 상대/현재 코스는 재조회하지 않는다. "
                    + "승인 전·삭제·탈퇴·다른 계정은 RUN-002. 승인 영수증이며 현재 주행 상태·승패가 아니다.")
    @GetMapping("/start")
    ApiResult<GhostStartApproval> get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return ApiResult.success(freeGhosts.receipt(owner(jwt),id).orElseGet(()->store.get(owner(jwt), id)));
    }

    private static UUID owner(Jwt jwt) {
        try { return UUID.fromString(jwt.getSubject()); }
        catch (RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
    }
}
