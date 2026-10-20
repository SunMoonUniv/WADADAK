package com.wadadak.course.internal.explore;

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
@RequestMapping("/api/v1/courses/search")
@RequiredArgsConstructor
class CourseSearchController {

    private final CourseMapRepository courseMapRepository;

    @Operation(summary = "코스 검색 (G1)",
            description = "이름에 검색어(query)가 들어간 활성 코스를 전국에서 찾는다(SEA-03). 공백과 대소문자는 보지 않아 "
                    + "`한강러닝`으로 `한강 러닝`도 찾는다. 초성 · 오탈자 · 동의어는 지원하지 않는다. "
                    + "정렬 · 현재 위치 · 카드 · 커서는 코스 목록(GET /api/v1/courses)과 같고, A3 필터는 쓰지 않는다. "
                    + "totalCount는 걸린 코스 수(`코스 검색 결과 N`)다. "
                    + "검색어가 공백을 빼고 2글자 미만, 가까운순인데 현재 위치가 없음, 잘못되거나 다른 정렬의 커서는 COMMON-001.")
    @GetMapping
    ApiResult<CourseSearchResult> search(
            @ParameterObject @Valid CourseSearchRequest search,
            @ParameterObject @Valid CourseListRequest order,
            @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(courseMapRepository.search(search.key(), order.sort(), order.origin(), page));
    }
}
