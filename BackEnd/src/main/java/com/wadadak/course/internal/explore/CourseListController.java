package com.wadadak.course.internal.explore;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/courses")
@RequiredArgsConstructor
class CourseListController {

    private final CourseMapRepository courseMapRepository;

    @Operation(summary = "코스 목록 (A2 · A6)",
            description = "출발점이 지도 범위 안에 있는 활성 코스 목록. 범위 · 필터는 지도 범위 안 코스와 같다(MAP-07). "
                    + "LATEST는 최근 등록순, NEAREST는 현재 위치(lat · lng)에서 출발점까지 가까운 순, "
                    + "RATING은 전체 기간 평점(소수 첫째 자리 반올림)이 높은 순이고 같으면 리뷰 수가 많은 순, 그다음 최근 등록순이다. "
                    + "리뷰가 없는 코스는 RATING에서 맨 뒤다. 정렬 값이 모두 같으면 ID순. "
                    + "카드의 averageRating은 전체 기간 평점(리뷰가 없으면 null), reviewCount는 리뷰 수다. "
                    + "다음 쪽은 nextCursor를 cursor로 보내고, 범위 · 필터 · 정렬 · 현재 위치는 첫 쪽과 같게 보낸다. "
                    + "인기순 · 실시간순과 카드의 현재 러너는 run의 도전 수 · 현재 러너 수 이벤트 뒤에 붙는다. "
                    + "범위 · 필터 오류, 가까운순인데 현재 위치가 없음, 잘못되거나 다른 정렬의 커서는 COMMON-001.")
    @GetMapping
    ApiResult<CursorSlice<CourseListItem>> list(
            @ParameterObject @Valid CourseMapRequest area,
            @ParameterObject @Valid CourseListRequest order,
            @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(courseMapRepository.list(area.requireValid(), order.sort(), order.origin(), page));
    }
}
