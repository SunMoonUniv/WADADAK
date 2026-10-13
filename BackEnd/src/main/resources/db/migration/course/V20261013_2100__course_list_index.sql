-- 코스 목록 최신순(A2 · A6)과 지도 범위 안 코스(A5)의 정렬 순서. 커서가 (등록 시각, ID) 다음부터 읽는다(개발 정책 6.3).
CREATE INDEX courses_created_at_idx ON course.courses (created_at DESC, id DESC) WHERE status = 'ACTIVE';
