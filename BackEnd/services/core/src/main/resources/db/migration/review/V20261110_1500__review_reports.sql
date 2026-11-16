-- 리뷰 신고(G2-1~G2-4). 다른 러너의 리뷰를 사유 5개 중 하나로 신고한다. 처리(삭제·문제 없음)는 운영자 화면에서 따로 붙인다.
CREATE TABLE review.review_reports
(
    id                 UUID         NOT NULL PRIMARY KEY,
    -- 신고한 리뷰. 리뷰가 지워지면(작성자 삭제 · 코스 삭제 · 작성자 탈퇴) 신고도 함께 지운다.
    review_id          UUID         NOT NULL REFERENCES review.reviews (id) ON DELETE CASCADE,
    -- 신고한 회원(member 모듈, FK 없음).
    reporter_member_id UUID         NOT NULL,
    reason             VARCHAR(20)  NOT NULL CHECK (reason IN ('ADVERTISING', 'ABUSE', 'PRIVACY', 'IRRELEVANT', 'OTHER')),
    -- 자세한 내용. 선택 입력, 100자까지.
    detail             VARCHAR(100),
    created_at         TIMESTAMPTZ  NOT NULL,
    updated_at         TIMESTAMPTZ  NOT NULL,
    -- 한 회원은 한 리뷰를 한 번만 신고한다. 다른 기기에서 동시에 신고해도 하나만 남는다(REVIEW-009).
    CONSTRAINT review_reports_review_reporter_uk UNIQUE (review_id, reporter_member_id)
);
-- 회원 탈퇴 때 그 회원이 한 신고를 지운다.
CREATE INDEX review_reports_reporter_member_id_idx ON review.review_reports (reporter_member_id);
