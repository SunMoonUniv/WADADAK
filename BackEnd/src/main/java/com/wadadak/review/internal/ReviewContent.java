package com.wadadak.review.internal;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.Set;

/**
 * 리뷰에서 사용자가 입력하는 내용. 수정(B10) 요청 본문이기도 하다. 범위를 벗어나면 COMMON-001.
 *
 * <p>[읽는 법] {@code record}는 값만 담는 불변 클래스다. 괄호 안 항목이 곧 필드이고, 생성자·getter({@code rating()})·equals가 자동으로 생긴다.
 * {@code @Min}·{@code @Max}·{@code @Size} 같은 검증 애너테이션은 컨트롤러에서 {@code @Valid}를 붙였을 때 동작하고,
 * 어기면 서비스까지 가지 않고 400 COMMON-001로 돌려준다(GlobalExceptionHandler).
 *
 * @param rating  전체 별점 1~5. 항목 평가 4개도 모두 1~5 필수
 * @param content 한줄 후기. 선택, 200자까지. 앞뒤 공백을 지우고 비어 있으면 없는 것으로 저장한다
 * @param tags    선택. 없으면 빈 목록
 */
record ReviewContent(
        @Min(1) @Max(5) int rating,
        @Min(1) @Max(5) int safetyRating,
        @Min(1) @Max(5) int roadRating,
        @Min(1) @Max(5) int lightingRating,
        @Min(1) @Max(5) int amenityRating,
        @Size(max = MAX_CONTENT_LENGTH) String content,
        Set<@NotNull ReviewTag> tags) {

    static final int MAX_CONTENT_LENGTH = 200;

    // 콤팩트 생성자: record가 만들어질 때마다 실행된다. 태그를 안 보내면(null) 빈 목록으로 바꿔 이후 코드가 null을 신경 쓰지 않게 한다
    ReviewContent {
        tags = tags == null ? Set.of() : Set.copyOf(tags);
    }

    /** 저장할 후기. 공백만 있으면 후기가 없는 것으로 본다. */
    String text() {
        return content == null || content.isBlank() ? null : content.strip();
    }
}
