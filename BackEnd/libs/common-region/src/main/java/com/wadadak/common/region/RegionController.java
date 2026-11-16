package com.wadadak.common.region;

import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirements;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** 시·군·구 검색. 지역 이름은 공개 정보라 로그인 없이 쓴다(가입 활동 지역, I6 지역 선택). */
@RestController
@RequestMapping("/api/v1/regions")
@RequiredArgsConstructor
class RegionController {

    private static final int SEARCH_LIMIT = 20;

    private final RegionDirectory regions;

    @Operation(summary = "시·군·구 검색 (가입 활동 지역, I6 지역 선택)",
            description = "이름이나 상위 구역 이름에 검색어가 들어간 시·군·구를 최대 20개. 이름이 정확히 같은 지역이 먼저 온다. "
                    + "로그인 없이 호출한다. 빈 검색어나 20자 초과는 COMMON-001.")
    @SecurityRequirements
    @GetMapping
    ApiResult<List<Region>> search(@RequestParam @NotBlank @Size(max = 20) String query) {
        return ApiResult.success(regions.searchSigungu(query, SEARCH_LIMIT));
    }
}
