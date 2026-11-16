-- 코스 자동 생성 분석 로그에 "만든 경로 전부"를 남긴다(논문 분석용, 2026-11-16).
-- 앱에는 최대 3개만 보내지만, 길찾기로는 수십 개를 만들고 거리 · 되돌아감 · 겹침으로 거른 뒤 점수순으로 고른다.
-- 이전 로그는 이 칸이 비어 있다(null).
ALTER TABLE course.planner_plan_logs
    -- 길찾기로 만든 경로 수
    ADD COLUMN generated_count INTEGER,
    -- 거리 · 되돌아감 조건을 통과한 경로 수
    ADD COLUMN passed_count    INTEGER,
    -- 만든 경로 전부(만든 순서): fate(PICKED · OUT_OF_RANGE · TOO_MUCH_RETRACE · SIMILAR_TO_EXISTING · SIMILAR_TO_PICKED ·
    -- NOT_EXAMINED), rank, 거리 · 되돌아감 · 큰길 · 점수 · 편의점 · 오르막 · 길 비율, points(2m로 줄인 경로 점)
    ADD COLUMN paths           JSONB;
