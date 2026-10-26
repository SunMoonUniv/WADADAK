package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.response.ApiResult;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/runs/ghost-candidates")
class OwnGhostCandidateController {
    private final OwnGhostCandidates candidates;
    OwnGhostCandidateController(OwnGhostCandidates candidates) { this.candidates = candidates; }

    @Operation(summary = "내 코스 완주 고스트 후보",
        description = "같은 코스/경로 버전의 본인 완주만 조회합니다. RECENT는 실제 시작 시각순, BEST는 코스 정수 초순. "
            + "커서 기본 20개/최대 50개이며 선택한 한 건의 ghost-playback에서 재생 적합성을 확인합니다.")
    @GetMapping("/own")
    ApiResult<OwnGhostCandidatePage> own(@AuthenticationPrincipal Jwt jwt,
            @RequestParam UUID courseId, @RequestParam long courseVersion,
            @RequestParam(defaultValue = "RECENT") OwnGhostSort sort,
            @RequestParam(defaultValue = "ALL") OwnGhostPeriod period, @ParameterObject @Valid Cursorable page) {
        UUID owner;
        try { owner = UUID.fromString(jwt.getSubject()); }
        catch (RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
        return ApiResult.success(candidates.list(owner, courseId, courseVersion, sort, period, page));
    }
}
