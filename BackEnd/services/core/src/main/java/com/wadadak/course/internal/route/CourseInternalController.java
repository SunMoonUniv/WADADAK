package com.wadadak.course.internal.route;

import com.wadadak.common.response.ApiResult;
import com.wadadak.course.CourseApi;
import com.wadadak.course.CourseRouteSnapshot;
import io.swagger.v3.oas.annotations.Hidden;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * 서비스 사이 내부 API(MSA 분리 2단계, 개발 정책 11.3). 분리 뒤 run이 {@code CourseApiHttpClient}로 부른다.
 * 앱용이 아니라 Swagger에서 숨긴다. 켜는 값은 {@code app.common.internal-api.enabled}.
 */
@Hidden
@RestController
@RequestMapping("/internal/v1/courses")
@ConditionalOnProperty(name = "app.common.internal-api.enabled", havingValue = "true")
@RequiredArgsConstructor
class CourseInternalController {

    private final CourseApi courseApi;

    /** {@link CourseApi#getRouteForRun}. 없으면 COURSE-001, 공개 중이 아니면 COURSE-002 */
    @GetMapping("/{courseId}/route")
    ApiResult<CourseRouteSnapshot> route(@PathVariable UUID courseId) {
        return ApiResult.success(courseApi.getRouteForRun(courseId));
    }
}
