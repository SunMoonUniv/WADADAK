package com.wadadak.course.internal.explore;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/courses/members/{memberId}")
@RequiredArgsConstructor
class RunnerCourseController {

    private final RunnerCourseRepository repository;

    @Operation(summary = "다른 러너가 등록한 코스 (I3)",
            description = "I3 `등록한 코스`. 그 러너가 등록한 공개 중인 코스를 최근 등록순(같으면 ID순)으로 준다. "
                    + "삭제 예정 · 삭제된 코스는 빠진다(정책 공통 4). 코스는 공개 정보라 내 정보 공개 설정과 관계없이 보인다. "
                    + "카드의 `주행 N회`는 completionCount(완주 수, G4 `누적 주행`과 같다), averageRating은 전체 기간 평점"
                    + "(소수 첫째 자리 반올림, 리뷰가 없으면 null), route는 썸네일이다. 없는 회원이면 빈 목록이다. "
                    + "다음 쪽은 nextCursor를 cursor로 보낸다. 잘못된 커서 · 회원 ID COMMON-001.")
    @GetMapping
    ApiResult<CursorSlice<RunnerCourseItem>> list(@PathVariable UUID memberId, @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(repository.list(memberId, page));
    }

    @Operation(summary = "다른 러너가 등록한 코스 수 (I3 위 칸)",
            description = "I3 위 칸의 `등록 코스 N개`. 공개 중인 코스만 센다(MY `등록 코스`와 같다). 없는 회원이면 0이다. 잘못된 회원 ID COMMON-001.")
    @GetMapping("/summary")
    ApiResult<RunnerCourseSummary> summary(@PathVariable UUID memberId) {
        return ApiResult.success(repository.summary(memberId));
    }
}
