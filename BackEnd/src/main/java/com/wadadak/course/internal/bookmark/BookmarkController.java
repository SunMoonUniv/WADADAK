package com.wadadak.course.internal.bookmark;

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
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/** 저장한 코스 REST API(B1-09 · G5 · C8). 로그인한 본인의 저장만 다룬다. 토큰의 sub가 회원 ID다. */
@RestController
@RequestMapping("/api/v1/courses/bookmarks")
@RequiredArgsConstructor
class BookmarkController {

    private final BookmarkService service;

    @Operation(summary = "코스 저장 (B1-09)",
            description = "공개 중인 코스만 새로 저장한다. 내가 등록한 코스도 저장한다. 이미 저장한 코스면 저장 시각을 바꾸지 않고 그대로 둔다"
                    + "(그 사이 비공개가 됐어도 같다). 저장 수 제한은 없다. "
                    + "없는 코스 COURSE-001, 삭제 예정 · 삭제된 코스와 만료 시각이 지난 코스 COURSE-002.")
    @PutMapping("/{courseId}")
    ApiResult<Void> save(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID courseId) {
        service.save(memberId(jwt), courseId);
        return ApiResult.success();
    }

    @Operation(summary = "저장 해제 (B1-09 · G5 편집)",
            description = "courseIds(최대 100개, 같은 ID는 한 번)의 저장을 푼다. B1은 하나, G5 편집은 고른 코스를 한 번에 보낸다. "
                    + "코스 상태와 상관없이 풀리고, 저장하지 않은 코스는 그냥 넘어간다. courseIds가 없거나 100개를 넘거나 UUID가 아니면 COMMON-001.")
    @DeleteMapping
    ApiResult<Void> remove(@AuthenticationPrincipal Jwt jwt, @ParameterObject @Valid BookmarkIdsRequest request) {
        service.remove(memberId(jwt), request.ids());
        return ApiResult.success();
    }

    @Operation(summary = "저장 여부 (B1-09 버튼 · C8 카드)",
            description = "courseIds(최대 100개) 중 내가 저장한 코스 ID를 돌려준다. 순서는 정하지 않는다. "
                    + "courseIds가 없거나 100개를 넘거나 UUID가 아니면 COMMON-001.")
    @GetMapping("/status")
    ApiResult<List<UUID>> status(@AuthenticationPrincipal Jwt jwt, @ParameterObject @Valid BookmarkIdsRequest request) {
        return ApiResult.success(service.bookmarked(memberId(jwt), request.ids()));
    }

    @Operation(summary = "저장한 코스 (G5 · C8)",
            description = "공개 중인 코스와 삭제 예정 코스(만료됐거나 등록자가 삭제해 비공개, 24시간 뒤 삭제)를 준다. 삭제가 끝난 코스는 빠진다. "
                    + "sort: RECENT 최근 저장순(처음) · NEAREST 가까운순(lat · lng 필요) · RATING 평점순(평점 → 리뷰 수, 리뷰 없으면 맨 뒤) · "
                    + "EXPIRING 만료 임박(만료가 가까운 순). 같으면 최근 저장순이고, 어느 정렬이든 삭제 예정 코스는 공개 중인 코스 뒤에 최근 저장순으로 온다. "
                    + "creatorNickname은 등록자 닉네임(탈퇴했으면 `탈퇴한 사용자`, 받지 못하면 null)이다. 다음 쪽은 nextCursor를 cursor로 보낸다. "
                    + "잘못된 커서 · 정렬, 가까운순인데 위치가 없음, 위도 · 경도 중 하나만 보냄 COMMON-001.")
    @GetMapping
    ApiResult<CursorSlice<BookmarkItem>> list(@AuthenticationPrincipal Jwt jwt, @ParameterObject BookmarkListRequest request,
                                              @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(service.list(memberId(jwt), request, page));
    }

    @Operation(summary = "저장한 코스 합계 (G5 위 칸)",
            description = "탭의 `저장한 코스 N`과 위 칸 `저장한 코스` · `만료 임박`. 공개 중인 코스만 센다(삭제 예정 코스는 목록에만 보인다, G4와 같다). "
                    + "만료 임박은 만료일까지 7일 이내(D-7 ~ D-0, Asia/Seoul)인 코스 수다.")
    @GetMapping("/summary")
    ApiResult<BookmarkSummary> summary(@AuthenticationPrincipal Jwt jwt) {
        return ApiResult.success(service.summary(memberId(jwt)));
    }

    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
