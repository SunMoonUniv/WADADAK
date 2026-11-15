package com.wadadak.review.internal;

import java.time.Instant;
import java.util.UUID;

/**
 * 이 코스에 대한 내 리뷰 상태. G2 상단 "내 리뷰"와 "리뷰 작성하기" 버튼이 어디로 갈지(B2 작성·B10 수정)를 정하는 데 쓴다.
 *
 * <p>앱은 이렇게 나눈다: {@code review}가 있으면 B10(근거 기록이 삭제됐으면 B10-1),
 * 없고 {@code eligibleRecord}가 있으면 B2, 둘 다 없으면 "충분히 달린 기록이 있어야 리뷰를 쓸 수 있어요" 안내.
 *
 * @param review              내 리뷰. 아직 쓰지 않았으면 {@code null}
 * @param sourceRecord        내 리뷰의 근거 기록. B10 상단에 보인다. 리뷰가 없거나 근거 기록이 삭제됐으면 {@code null}
 * @param sourceRecordDeleted 내 리뷰의 근거 기록이 삭제됐다(B10-1). 리뷰가 없으면 {@code false}
 * @param eligibleRecord      리뷰를 쓸 수 있는 내 기록 중 가장 최근 것. 없거나 숨김·삭제된 코스면 {@code null}
 */
record MyReview(ReviewCard review, CourseRun sourceRecord, boolean sourceRecordDeleted, CourseRun eligibleRecord) {

    /**
     * 이 코스를 달린 내 기록 1건. B2·B10 상단에 "5.2km · 2026.09.08 완주 100% · 27:14"처럼 보여준다.
     * 작성할 때는 {@code eligibleRecord.runRecordId}를 리뷰 작성 요청의 {@code sourceRunRecordId}로 보낸다.
     *
     * @param courseElapsedSeconds 코스 총 소요시간(정수 초)
     * @param completed            서버 완주 판정. 완주하지 않았어도 리뷰 자격이 있을 수 있다(정책 5.1)
     * @param endedAt              주행이 끝난 시각
     */
    record CourseRun(UUID runRecordId, int courseDistanceMeters, int courseElapsedSeconds,
                     int progressPercent, boolean completed, Instant endedAt) {
    }
}
