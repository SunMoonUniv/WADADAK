package com.wadadak.review;

import com.wadadak.common.exception.ErrorCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

/**
 * 리뷰 에러 코드(정책 공통 5). 별점·항목 평가 범위 같은 입력 형식 오류는 공통 검증(COMMON-001)으로 처리한다.
 */
@Getter
@RequiredArgsConstructor
public enum ReviewErrorCode implements ErrorCode {
    NOT_ELIGIBLE(HttpStatus.FORBIDDEN, "REVIEW-001", "이 코스를 충분히 달린 기록이 있어야 리뷰를 쓸 수 있습니다."),
    ALREADY_REVIEWED(HttpStatus.CONFLICT, "REVIEW-002", "이미 이 코스에 리뷰를 썼습니다. 기존 리뷰를 수정해 주세요."),
    REVIEW_NOT_FOUND(HttpStatus.NOT_FOUND, "REVIEW-003", "리뷰를 찾을 수 없습니다."),
    NOT_REVIEW_OWNER(HttpStatus.FORBIDDEN, "REVIEW-004", "내가 쓴 리뷰만 수정하거나 삭제할 수 있습니다."),
    COURSE_NOT_REVIEWABLE(HttpStatus.CONFLICT, "REVIEW-005", "비공개되었거나 삭제된 코스에는 리뷰를 쓸 수 없습니다."),
    TOO_MANY_PHOTOS(HttpStatus.BAD_REQUEST, "REVIEW-006", "리뷰 사진은 5장까지 올릴 수 있습니다."),
    PHOTO_NOT_FOUND(HttpStatus.BAD_REQUEST, "REVIEW-007", "사진을 찾을 수 없습니다. 다시 올려 주세요.");

    private final HttpStatus status;
    private final String code;
    private final String message;
}
