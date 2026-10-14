package com.wadadak.review.internal;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.response.ApiResult;
import com.wadadak.common.storage.UploadForm;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * 리뷰 REST API. 앱의 HTTP 요청을 받아 서비스에 넘기고, 결과를 {@link ApiResult}로 감싸 JSON으로 돌려준다.
 *
 * <p>URL은 review 모듈 prefix인 {@code /api/v1/reviews} 아래에만 둔다. 나중에 review를 별도 서버로 떼어내면
 * 게이트웨이가 이 prefix로 요청을 보낸다(개발 정책 7장). 모든 요청은 로그인(JWT)이 필요하다.
 */
@RestController // 메서드가 돌려준 값을 JSON 응답 본문으로 바꾼다
@RequestMapping("/api/v1/reviews") // 이 클래스 메서드들의 공통 URL 앞부분
@RequiredArgsConstructor
class ReviewController {

    private final ReviewService reviewService;
    private final ReviewQueryService queryService;

    @Operation(summary = "코스 평점 요약 (B8·G2 상단)",
            description = "전체 별점 평균·리뷰 수·별점별 분포·항목별 평균(안전성·도로 상태·야간 조명·편의시설). "
                    + "평균은 소수 첫째 자리 반올림. 리뷰가 없거나 숨김·삭제된 코스면 리뷰 수 0, 평균은 null.")
    @GetMapping("/summary")
    ApiResult<ReviewSummary> summary(@RequestParam UUID courseId) { // @RequestParam: URL의 ?courseId=… 값
        return ApiResult.success(queryService.summary(courseId));
    }

    @Operation(summary = "코스 리뷰 목록 (B8·G2)",
            description = "커서 페이징. 정렬·사진 조건을 바꾸거나 새로고침할 때는 cursor 없이 첫 페이지부터 다시 조회한다. "
                    + "sort: LATEST 최신순(기본) / HIGHEST 높은 평점 / LOWEST 낮은 평점(같은 별점은 최신순). "
                    + "photoOnly=true면 사진이 있는 리뷰만, excludeMine=true면 내 리뷰를 뺀다(G2 \"다른 러너 리뷰\"). "
                    + "photos는 보이는 순서대로(key·url). completedCount가 0이면 주행 횟수를 표시하지 않는다. 닉네임을 못 가져오면 null이다. "
                    + "숨김·삭제된 코스는 빈 목록. 잘못된 sort·cursor·size는 COMMON-001.")
    @GetMapping
    ApiResult<CursorSlice<ReviewCard>> list(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam UUID courseId,
            @RequestParam(defaultValue = "LATEST") ReviewSort sort, // 안 보내면 최신순
            @RequestParam(defaultValue = "false") boolean photoOnly,
            @RequestParam(defaultValue = "false") boolean excludeMine,
            @ParameterObject @Valid Cursorable page) { // ?cursor=…&size=… 를 한 객체로 받는다
        return ApiResult.success(queryService.list(courseId, sort, photoOnly, excludeMine, memberId(jwt), page));
    }

    @Operation(summary = "이 코스의 내 리뷰 (G2 내 리뷰·B2/B10 진입)",
            description = "review가 있으면 수정(B10), sourceRecordDeleted=true면 B10-1 안내. 수정 화면은 review 값으로 채우고, "
                    + "남길 사진은 review.photos[].key를 수정 요청의 photoKeys로 다시 보낸다. "
                    + "review가 없고 eligibleRecord가 있으면 작성(B2): eligibleRecord.runRecordId를 작성 요청의 sourceRunRecordId로 보낸다. "
                    + "둘 다 없으면 아직 리뷰 자격이 없다. eligibleRecord는 리뷰 자격이 있는 내 기록 중 가장 최근 것이고, "
                    + "숨김·삭제된 코스면 null이다. 내 리뷰는 숨김 코스여도 돌려준다(삭제할 수 있게).")
    @GetMapping("/me")
    ApiResult<MyReview> mine(@AuthenticationPrincipal Jwt jwt, @RequestParam UUID courseId) {
        return ApiResult.success(queryService.mine(memberId(jwt), courseId));
    }

    @Operation(summary = "코스별 평점 일괄 조회 (A5 지도 핀)",
            description = "courseIds=a,b,c 처럼 쉼표로 최대 100개. 요청한 코스마다 한 줄씩 돌려준다. "
                    + "리뷰가 없거나 숨김·삭제된 코스는 averageRating null. 코스 카드의 평점·리뷰 수는 코스 목록 API를 쓴다. "
                    + "100개 초과는 COMMON-001.")
    @GetMapping("/ratings")
    ApiResult<List<CourseRating>> ratings(@RequestParam Set<UUID> courseIds) {
        return ApiResult.success(queryService.ratings(courseIds));
    }

    // @Operation: Swagger(API 문서)에 보이는 설명. 앱 담당이 이걸 보고 연동한다
    @Operation(summary = "리뷰 작성 (B2)",
            description = "회원당 코스별 1개. 전체 별점과 항목 평가 4개(안전성·도로 상태·야간 조명·편의시설)는 1~5 필수, "
                    + "한줄 후기는 선택(200자), 태그는 NIGHT_VIEW·FEW_SIGNALS·GOOD_SURFACE·CROWDED 중 여러 개. "
                    + "sourceRunRecordId는 이 코스에서 리뷰 자격을 얻은 내 기록(삭제되지 않은 것)이어야 한다. "
                    + "사진은 photo-uploads로 올린 키를 보이는 순서대로 photoKeys에 담는다(선택, 5장까지). "
                    + "자격 없음 REVIEW-001, 이미 작성 002(수정 안내), 숨김·삭제 코스 005, 사진 5장 초과 006, "
                    + "올라오지 않았거나 다른 리뷰의 사진 007, 형식 오류 COMMON-001.")
    @PostMapping
    ApiResult<ReviewView> write(
            @AuthenticationPrincipal Jwt jwt, // 로그인 토큰. 스프링 시큐리티가 서명을 검증한 뒤 넣어 준다
            @Valid @RequestBody WriteReviewRequest request) { // @RequestBody: JSON 본문 → record, @Valid: @Min·@Size 등 검사
        return ApiResult.success(reviewService.write(memberId(jwt), request));
    }

    @Operation(summary = "리뷰 수정 (B10)",
            description = "별점·항목 평가·후기·태그·사진을 모두 보낸다(전체 교체). 남길 사진은 응답의 photos[].key를 다시 보내고, "
                    + "빠진 사진은 파일까지 지운다. 근거 기록이 삭제돼도 수정할 수 있다(B10-1). "
                    + "작성 시각은 바뀌지 않는다. 최고 진행도는 지금 남은 기록이 더 높을 때만 올라간다. "
                    + "없음 REVIEW-003, 내 리뷰 아님 004, 숨김·삭제 코스 005, 사진 006·007, 형식 오류 COMMON-001.")
    @PutMapping("/{reviewId}") // PUT /api/v1/reviews/{reviewId}
    ApiResult<ReviewView> edit(@AuthenticationPrincipal Jwt jwt,
                               @PathVariable UUID reviewId, // URL의 {reviewId} 자리 값
                               @Valid @RequestBody ReviewContent request) {
        return ApiResult.success(reviewService.edit(memberId(jwt), reviewId, request));
    }

    @Operation(summary = "리뷰 사진 업로드 폼 (B2·B10)",
            description = "사진 한 장마다 받는다. 앱은 사진을 JPEG로 바꾸고 위치 등 EXIF를 지운 뒤, url에 multipart/form-data로 "
                    + "fields를 모두 넣고 파일을 마지막 file 필드로 붙여 POST한다(10분 안에, 50MB 이하, image/jpeg만). "
                    + "올린 뒤 key를 리뷰 작성·수정의 photoKeys에 담는다. 사진은 로그인 없이 받는다.")
    @PostMapping("/photo-uploads")
    ApiResult<UploadForm> photoUpload() {
        return ApiResult.success(reviewService.photoUploadForm());
    }

    @Operation(summary = "리뷰 삭제 (B10)",
            description = "사진도 함께 지운다. 지운 뒤에는 같은 코스에 다시 작성할 수 있다. 없음 REVIEW-003, 내 리뷰 아님 004.")
    @DeleteMapping("/{reviewId}")
    ApiResult<Void> delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID reviewId) {
        reviewService.delete(memberId(jwt), reviewId);
        return ApiResult.success();
    }

    /** 토큰의 sub가 회원 ID다(개발 정책 7장). member 모듈을 호출하지 않고 토큰만으로 누구인지 안다. */
    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
