package com.wadadak.course.internal.mine;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/courses/mine")
@RequiredArgsConstructor
class MyCourseController {

    private final MyCourses myCourses;

    @Operation(summary = "내가 등록한 코스 (G4)",
            description = "공개 중인 코스와 삭제 예정 코스(만료됐거나 내가 삭제해 비공개, 24시간 뒤 삭제)를 준다. 삭제가 끝난 코스는 빠진다. "
                    + "만료 임박(만료일까지 7일 이내, D-7 ~ D-0, Asia/Seoul) 공개 코스가 먼저 오고 만료가 가까운 순, "
                    + "나머지(삭제 예정 포함)는 최근 등록순, 같으면 ID순이다. "
                    + "카드의 `누적 주행`은 completionCount(완주 수), `최근 주행`은 lastCompletedOn(마지막 완주 날, 없으면 null)이다. "
                    + "완주 날짜를 저장하기 전(이 API 배포 전)의 완주는 lastCompletedOn에 들어가지 않는다. "
                    + "다음 쪽은 nextCursor를 cursor로 보낸다. 잘못된 커서 COMMON-001.")
    @GetMapping
    ApiResult<CursorSlice<MyCourseItem>> list(@AuthenticationPrincipal Jwt jwt, @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(myCourses.list(memberId(jwt), page));
    }

    @Operation(summary = "내가 등록한 코스 합계 (G4 위 칸)",
            description = "탭의 `등록한 코스 N`과 위 칸 `등록 코스` · `누적 주행` · `만료 임박`. 공개 중인 코스만 센다(삭제 예정 코스는 목록에만 보인다). "
                    + "누적 주행은 그 코스들의 완주 수 합, 만료 임박은 만료일까지 7일 이내(D-7 ~ D-0, Asia/Seoul)인 코스 수다.")
    @GetMapping("/summary")
    ApiResult<MyCourseSummary> summary(@AuthenticationPrincipal Jwt jwt) {
        return ApiResult.success(myCourses.summary(memberId(jwt)));
    }

    static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
