package com.wadadak.run.internal.recording;

import com.wadadak.common.response.ApiResult;
import com.wadadak.run.internal.RunContracts.GpsSourceLinkStatus;
import java.util.UUID;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/runs/records")
class GpsSourceLinkController {
    private final GpsSourceLinkService links;
    GpsSourceLinkController(GpsSourceLinkService links) {this.links=links;}
    @GetMapping("/{id}/gps-course-link")
    ApiResult<GpsSourceLinkStatus> status(@AuthenticationPrincipal Jwt jwt,@PathVariable UUID id) {
        return ApiResult.success(links.status(UUID.fromString(jwt.getSubject()),id));
    }
}
