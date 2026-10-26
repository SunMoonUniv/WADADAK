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
            description = "출발점이 지도 범위 안에 있는 활성 코스 목록. 범위 · 필터(G6에서 고른 query · regionCode 포함)는 지도 범위 안 코스와 같다(MAP-07). "
                    + "POPULAR는 도전 수(코스 러닝을 실제로 시작한 세션 수)가 많은 순이고 같으면 조회 수, 리뷰 수가 많은 순, 그다음 최근 등록순이다. "
                    + "RATING은 전체 기간 평점(소수 첫째 자리 반올림)이 높은 순이고 같으면 리뷰 수가 많은 순, 그다음 최근 등록순이다. "
                    + "리뷰가 없는 코스는 RATING에서 맨 뒤다. NEAREST는 현재 위치(lat · lng)에서 출발점까지 가까운 순, LATEST는 최근 등록순, "
                    + "LIVE는 지금 달리는 러너가 많은 순이고 같으면 POPULAR(전체 기간) 순서다. 정렬 값이 모두 같으면 ID순. "
                    + "POPULAR에만 기간 startDate · endDate(FIL-09, yyyy-MM-dd, Asia/Seoul, 둘 다 포함, 하나만 보내도 된다)를 줄 수 있다. "
                    + "주면 그 기간의 도전 수 · 조회 수 · 리뷰 수로 같은 규칙에 따라 정렬하고, 코스는 빼지 않는다(기간에 값이 없으면 뒤로). "
                    + "카드의 averageRating은 전체 기간 평점(리뷰가 없으면 null), reviewCount는 리뷰 수, activeRunners는 지금 달리는 러너 수다. "
                    + "다음 쪽은 nextCursor를 cursor로 보내고, 범위 · 필터 · 정렬 · 기간 · 현재 위치는 첫 쪽과 같게 보낸다. "
                    + "범위 · 필터 오류, 가까운순인데 현재 위치가 없음, POPULAR가 아닌데 기간을 보냄, 기간 시작일이 종료일보다 늦음, "
                    + "잘못되거나 다른 정렬의 커서는 COMMON-001.")
    @GetMapping
    ApiResult<CursorSlice<CourseListItem>> list(
            @ParameterObject @Valid CourseMapRequest area,
            @ParameterObject @Valid CourseListRequest order,
            @ParameterObject CourseListPeriod period,
            @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(courseMapRepository.list(area.requireValid(), order.sort(), period.requireFor(order.sort()),
                order.origin(), page));
    }
}
