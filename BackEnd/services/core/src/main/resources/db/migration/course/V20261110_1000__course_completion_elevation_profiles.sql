-- 완주로 만든 고도 프로필(B1-03, 정책 문서 제4부 4.1 `B1-03 고도 프로필`).
-- 그린 코스와 등록 기록에 고도가 부족했던 GPS 코스는 run이 보낸 완주 경로(CourseRunTrackEvent) 중 고도가 충분한 첫 완주로 한 번 만들고 바꾸지 않는다.
-- 경로는 저장하지 않는다. 코스 하나에 한 줄이라 늦게 온 완주는 ON CONFLICT DO NOTHING으로 버린다. 행을 고치지 않아 updated_at이 없다.
CREATE TABLE course.completion_elevation_profiles
(
    course_id    UUID        NOT NULL PRIMARY KEY REFERENCES course.courses (id),
    -- gps_course_sources.elevation_profile_json과 같은 모양(gainMeters, samplesMeters 18개)
    profile_json TEXT        NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL
);
