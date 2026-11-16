-- GPS 주행 등록 코스의 출처(정책 공통 3, 정책 문서 제4부 4.1 `F7 GPS 코스 등록 저장`).
-- 같은 러닝 기록은 한 번만 코스로 만든다. 코스 행은 지워져도 DELETED로 남으므로 이 행도 지우지 않는다.
CREATE TABLE course.gps_course_sources
(
    course_id            UUID        NOT NULL PRIMARY KEY REFERENCES course.courses (id),
    -- run 모듈의 러닝 기록 ID라 FK를 걸지 않는다(개발 정책 2장).
    run_record_id        UUID        NOT NULL,
    -- 등록한 회원. B6 · 결과 화면의 `이미 등록됨`을 회원별로 찾는다.
    member_id            UUID        NOT NULL,
    -- 앱이 보낸 원본 경로 조각(course-source segments, 점마다 위도·경도·정확도·고도·고도 정확도) JSON.
    -- courses.route는 빈칸을 잇고 점을 줄인 경로라 고도를 다시 만들 수 없다. 고도 프로필(보류)을 나중에 만들 때 쓴다.
    source_segments_json TEXT        NOT NULL,
    created_at           TIMESTAMPTZ NOT NULL,
    updated_at           TIMESTAMPTZ NOT NULL,
    CONSTRAINT gps_course_sources_run_record_uk UNIQUE (run_record_id)
);

CREATE INDEX gps_course_sources_member_id_idx ON course.gps_course_sources (member_id);
