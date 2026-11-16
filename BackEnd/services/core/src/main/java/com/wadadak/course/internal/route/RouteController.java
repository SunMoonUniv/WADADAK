package com.wadadak.course.internal.route;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/courses/routes")
@RequiredArgsConstructor
class RouteController {

    private final RouteService routeService;

    @Operation(summary = "최종 경로 생성 (B3 다음)",
            description = "입력점을 순서대로 직선으로 이어 경로·거리·1km 표지를 돌려준다. 저장하지 않는다. "
                    + "입력점 2개 미만 COURSE-003, 1km 미만 COURSE-004, 100km 초과 COURSE-005.")
    @PostMapping
    ApiResult<GeneratedRoute> generate(@Valid @RequestBody RouteRequest request) {
        return ApiResult.success(routeService.generateCustom(request.anchorPoints()));
    }
}
