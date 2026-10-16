package com.wadadak.course.internal.detail;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/courses")
@RequiredArgsConstructor
class CourseDetailController {

    private final CourseDetailService courseDetailService;

    @Operation(summary = "코스 상세 (B1)",
            description = "이름 · 유형 · 난이도 · 태그(FIL-04 순서) · 거리 · 경로(첫 점이 출발점) · 1km 표지 · 공개 만료 시각 · 등록자 닉네임. "
                    + "등록자가 탈퇴했으면 닉네임은 `탈퇴한 사용자`, 회원 정보를 받지 못하면 null. "
                    + "평점 · 리뷰 수 · 항목 평가는 리뷰 API(/api/v1/reviews/summary), 평균 페이스 · 현재 러너는 코스 통계(F11) 뒤에 붙는다. "
                    + "없는 코스 COURSE-001(404), 비공개 · 삭제된 코스 COURSE-002(409), 잘못된 ID COMMON-001.")
    @GetMapping("/{courseId}")
    ApiResult<CourseDetail> detail(@PathVariable UUID courseId) {
        return ApiResult.success(courseDetailService.detail(courseId));
    }
}
