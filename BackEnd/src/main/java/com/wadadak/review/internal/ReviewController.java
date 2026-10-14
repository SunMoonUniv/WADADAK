package com.wadadak.review.internal;

import com.wadadak.common.response.ApiResult;
import com.wadadak.common.storage.UploadForm;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

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
