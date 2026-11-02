-- 저장한 코스(B1-09 · G5 · C8, 정책 문서 4.1 `저장한 코스 API`). 회원이 코스를 저장하면 한 줄이다.
-- 새로 저장할 수 있는 코스는 공개 중인 코스뿐이고, 이미 저장한 코스는 비공개(삭제 예정)가 돼도 삭제가 끝날 때까지 남는다.
-- 코스가 DELETED가 되면 그 코스의 줄을, 회원이 탈퇴하면 그 회원의 줄을 지운다. 저장 수 제한은 없다.
CREATE TABLE course.course_bookmarks
(
    -- member 모듈의 회원 ID. 다른 스키마라 FK는 없다
    member_id  UUID        NOT NULL,
    course_id  UUID        NOT NULL REFERENCES course.courses (id),
    -- 저장한 시각(최근 저장순). 이미 저장한 코스를 다시 저장해도 바꾸지 않는다
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (member_id, course_id)
);

-- 코스 삭제가 끝나면 그 코스의 저장을 지운다
CREATE INDEX course_bookmarks_course_id_idx ON course.course_bookmarks (course_id);
