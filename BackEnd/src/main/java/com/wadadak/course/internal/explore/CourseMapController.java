package com.wadadak.course.internal.explore;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/courses/map")
@RequiredArgsConstructor
class CourseMapController {

    private final CourseMapRepository courseMapRepository;

    @Operation(summary = "지도 범위 안 코스 (A2·A5 지도)",
            description = "출발점이 지도 범위 안에 있는 활성 코스의 수와 이름·경로를 돌려준다. 필터(FIL-02~05)를 주면 조건에 맞는 코스만 센다. "
                    + "코스는 최대 100개, 최근 등록순. 좌표 범위를 벗어났거나 남서쪽 끝이 북동쪽 끝보다 크거나 거리 하한이 상한보다 크면 COMMON-001.")
    @GetMapping
    ApiResult<CourseMap> find(@ParameterObject @Valid CourseMapRequest request) {
        return ApiResult.success(courseMapRepository.find(request.requireValid()));
    }
}
