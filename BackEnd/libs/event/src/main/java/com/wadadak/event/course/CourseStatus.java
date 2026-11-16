package com.wadadak.event.course;

/**
 * 코스 공개 상태. {@code ACTIVE → HIDDEN → DELETED} 한 방향으로만 바뀐다(정책 공통 4, 숨김 해제·삭제 취소 없음).
 */
public enum CourseStatus {
    /** 지도·목록·검색·상세·신규 러닝에 노출 */
    ACTIVE,
    /** 비공개. 신규 노출·진입 차단, 24시간 뒤 {@link #DELETED} */
    HIDDEN,
    /** 삭제 확정. 행은 남고 통계·리뷰·랭킹은 제거 */
    DELETED
}
