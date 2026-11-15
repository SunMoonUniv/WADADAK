-- GPS 코스 고도 프로필(B1-03, 정책 문서 제4부 4.1 `B1-03 고도 프로필`). 등록 때 source_segments_json으로 한 번 만든다.
-- 고도가 부족하면 JSON null이다. 이 열을 넣기 전에 등록한 코스는 NULL로 두고, 서버가 켜질 때 원본으로 채운다.
ALTER TABLE course.gps_course_sources ADD COLUMN elevation_profile_json TEXT;
