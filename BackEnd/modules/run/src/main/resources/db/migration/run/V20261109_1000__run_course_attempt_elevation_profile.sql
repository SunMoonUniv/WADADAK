-- 준비 때 코스에 고도 프로필이 이미 있었는지. 있으면 완주 경로(CourseRunTrackEvent)를 보내지 않는다. 기존 시도는 없음으로 본다(보낸다)
ALTER TABLE run.course_attempts ADD COLUMN has_elevation_profile boolean NOT NULL DEFAULT false;
