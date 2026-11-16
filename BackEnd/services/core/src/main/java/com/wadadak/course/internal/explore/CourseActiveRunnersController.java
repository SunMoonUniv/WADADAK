package com.wadadak.course.internal.explore;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/courses/active-runners")
@RequiredArgsConstructor
class CourseActiveRunnersController {

    private final CourseMapRepository courseMapRepository;

    @Operation(summary = "코스별 현재 러너 수 (홈 1분 갱신)",
            description = "홈이 보이는 동안 1분마다 카드의 현재 러너 수만 새로 받는다(공통 7 · HCR-05). "
                    + "courseIds(최대 100개, 같은 ID는 한 번)의 코스 중 공개 중인 코스만 돌려주고, 없거나 공개 중이 아닌 코스는 빠진다. "
                    + "activeRunners는 목록 카드와 같은 값이다. courseIds가 없거나 100개를 넘거나 UUID가 아니면 COMMON-001.")
    @GetMapping
    ApiResult<List<CourseActiveRunners>> find(@ParameterObject @Valid CourseActiveRunnersRequest request) {
        return ApiResult.success(courseMapRepository.activeRunners(request.ids()));
    }
}
