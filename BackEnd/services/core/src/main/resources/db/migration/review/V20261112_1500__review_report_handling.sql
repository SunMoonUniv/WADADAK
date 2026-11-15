-- 운영자 신고 처리(ADM-2-1 · ADM-2-2). 신고마다 처리 상태 · 메모 · 처리 시각을 남기고,
-- 리뷰를 지운 뒤에도 무엇을 지웠는지 보이게 신고할 때의 리뷰 내용을 함께 저장한다.

-- 운영자가 리뷰를 지우면 신고 기록이 남아야 해서 FK(ON DELETE CASCADE)를 뗀다.
-- 대신 작성자 삭제 · 코스 삭제 때는 대기 신고만 지우고(ReviewService · ReviewEventHandler), 처리한 신고는 남긴다.
ALTER TABLE review.review_reports
    DROP CONSTRAINT review_reports_review_id_fkey;

ALTER TABLE review.review_reports
    -- 신고할 때의 리뷰. 리뷰가 지워진 뒤 운영자 화면에 이 값을 보인다.
    ADD COLUMN course_id         UUID,
    ADD COLUMN review_member_id  UUID,
    ADD COLUMN review_rating     INTEGER,
    ADD COLUMN review_content    VARCHAR(200),
    ADD COLUMN review_created_at TIMESTAMPTZ,
    -- 대기 / 삭제함(운영자가 리뷰를 지움) / 문제 없음. 리뷰 하나의 대기 신고를 한꺼번에 처리한다.
    ADD COLUMN status            VARCHAR(10) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'DELETED', 'DISMISSED')),
    -- 처리 메모. 선택 입력, 200자까지.
    ADD COLUMN memo              VARCHAR(200),
    ADD COLUMN handled_at        TIMESTAMPTZ;

-- 이미 쌓인 신고는 지금 리뷰 내용으로 채운다(FK가 있었으니 리뷰가 모두 있다).
UPDATE review.review_reports rr
SET course_id         = r.course_id,
    review_member_id  = r.member_id,
    review_rating     = r.rating,
    review_content    = r.content,
    review_created_at = r.created_at
FROM review.reviews r
WHERE r.id = rr.review_id;

ALTER TABLE review.review_reports
    ALTER COLUMN course_id SET NOT NULL,
    ALTER COLUMN review_member_id SET NOT NULL,
    ALTER COLUMN review_rating SET NOT NULL,
    ALTER COLUMN review_created_at SET NOT NULL,
    ADD CONSTRAINT review_reports_handled_ck CHECK ((status = 'PENDING') = (handled_at IS NULL));

-- 코스 삭제 때 그 코스의 대기 신고를 지운다.
CREATE INDEX review_reports_course_id_idx ON review.review_reports (course_id);
-- 작성자 탈퇴 때 그 회원 리뷰에 달린 신고(리뷰 내용 복사본)를 지운다.
CREATE INDEX review_reports_review_member_id_idx ON review.review_reports (review_member_id);
