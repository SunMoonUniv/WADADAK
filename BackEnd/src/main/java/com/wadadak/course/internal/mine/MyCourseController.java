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
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/courses")
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
    @GetMapping("/mine")
    ApiResult<CursorSlice<MyCourseItem>> list(@AuthenticationPrincipal Jwt jwt, @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(myCourses.list(memberId(jwt), page));
    }

    @Operation(summary = "내가 등록한 코스 합계 (G4 위 칸)",
            description = "탭의 `등록한 코스 N`과 위 칸 `등록 코스` · `누적 주행` · `만료 임박`. 공개 중인 코스만 센다(삭제 예정 코스는 목록에만 보인다). "
                    + "누적 주행은 그 코스들의 완주 수 합, 만료 임박은 만료일까지 7일 이내(D-7 ~ D-0, Asia/Seoul)인 코스 수다.")
    @GetMapping("/mine/summary")
    ApiResult<MyCourseSummary> summary(@AuthenticationPrincipal Jwt jwt) {
        return ApiResult.success(myCourses.summary(memberId(jwt)));
    }

    @Operation(summary = "코스 수정 (B7)",
            description = "이름 · 난이도 · 특징을 모두 보낸다(전체 교체). 경로 · 유형 · 만료일은 바뀌지 않고, 바꾼 값은 지도 · 목록 · 상세에 바로 보인다. "
                    + "응답은 바뀐 G4 카드 값이다. 이름 길이 · 형식 오류 COMMON-001, 내 코스가 아님 COMMON-003, 없는 코스 COURSE-001, "
                    + "삭제 예정 · 삭제 · 만료된 코스 COURSE-002, 다른 공개 코스와 같은 이름(공백 · 대소문자 무시) COURSE-006. "
                    + "지금 이 코스 이름은 그대로 둬도 된다. 이름 확인은 name-availability에 courseId를 함께 보낸다.")
    @PutMapping("/{courseId}")
    ApiResult<MyCourseItem> edit(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID courseId,
                                 @Valid @RequestBody EditCourseRequest request) {
        return ApiResult.success(myCourses.edit(memberId(jwt), courseId, request));
    }

    @Operation(summary = "코스 삭제 (B7)",
            description = "공개 중인 코스를 바로 비공개로 바꾸고 24시간 뒤 지운다(만료와 같다, 정책 공통 4). "
                    + "지도 · 목록 · 검색 · 상세와 새 러닝 시작은 바로 막히고, 이미 시작한 러닝과 개인 기록은 남는다. "
                    + "삭제되면 코스 통계 · 리뷰 · 랭킹도 지워진다. 응답은 삭제 예정으로 바뀐 G4 카드 값(status HIDDEN, "
                    + "statusReason USER_DELETED, deleteAt)이다. 이미 삭제 예정이면 바꾸지 않고 그 값을 돌려준다. "
                    + "내 코스가 아님 COMMON-003, 없는 코스 COURSE-001, 삭제가 끝난 코스 COURSE-002.")
    @DeleteMapping("/{courseId}")
    ApiResult<MyCourseItem> delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID courseId) {
        return ApiResult.success(myCourses.delete(memberId(jwt), courseId));
    }

    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
