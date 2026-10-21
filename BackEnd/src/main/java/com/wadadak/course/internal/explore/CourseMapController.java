package com.wadadak.course.internal.explore;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/courses/map")
@RequiredArgsConstructor
class CourseMapController {

    private final CourseMapRepository courseMapRepository;

    @Operation(summary = "지도 범위 안 코스 (A2·A5 지도)",
            description = "출발점이 지도 범위 안에 있는 활성 코스의 수와 코스를 돌려준다. 코스 값은 목록(GET /api/v1/courses) 카드와 같아 "
                    + "지도에서 코스를 고르면(A5) 바로 카드로 보이고, 이름표의 평점도 여기서 읽는다(averageRating). "
                    + "필터(FIL-02~05)를 주면 조건에 맞는 코스만 센다. minRating은 전체 기간 평점(소수 첫째 자리 반올림)이 "
                    + "그 값 이상인 코스만 남기고, 리뷰가 없는 코스는 뺀다. "
                    + "코스는 최대 100개, 인기순(전체 기간: 도전 수 → 조회 수 → 리뷰 수가 많은 순, 그다음 최근 등록순 · ID순). "
                    + "앱은 이름표가 겹치면 앞 코스를 보인다(MAP-03). 좌표 범위를 벗어났거나 남서쪽 끝이 북동쪽 끝보다 크거나 거리 하한이 상한보다 크면 COMMON-001.")
    @GetMapping
    ApiResult<CourseMap> find(@ParameterObject @Valid CourseMapRequest request) {
        return ApiResult.success(courseMapRepository.find(request.requireValid()));
    }

    @Operation(summary = "지도 범위 안 지역별 코스 수 (A4 지도 축소)",
            description = "지도 범위 안 코스(출발점 기준)를 출발점 지역별로 센다. 범위·필터는 지도 범위 안 코스와 같다. "
                    + "CITY는 특별·광역·특별자치시를 통째로, 도는 시·군마다(전남광주통합특별시는 도처럼 세고 옛 광주광역시의 구는 '광주' 하나), "
                    + "DISTRICT는 시·군·구마다 하나. 코스가 많은 지역부터.")
    @GetMapping("/regions")
    ApiResult<RegionCounts> regions(
            @ParameterObject @Valid CourseMapRequest request,
            @Parameter(description = "CITY: 축척 2km보다 넓을 때, DISTRICT: 축척 2km부터 500m 전까지(MAP-02)") @RequestParam RegionLevel level) {
        return ApiResult.success(courseMapRepository.countByRegion(request.requireValid(), level));
    }
}
