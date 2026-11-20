-- 코스 자동 생성 분석 로그: 사용자가 후보로 코스를 실제로 등록했는지(논문 분석용, 2026-11-20).
-- 코스를 등록하면 같은 사람이 1시간 안에 한 코스 찾기의 후보와 등록 경로를 비교해, 85% 이상 겹치는 후보가 있으면 표시한다.
-- 찾기만 하고 등록하지 않았거나 후보를 많이 고쳐 등록했으면 비어 있다.
ALTER TABLE course.planner_plan_logs
    -- 등록한 코스 ID. 코스가 나중에 지워져도 남긴다(그래서 FK가 없다)
    ADD COLUMN registered_course_id UUID,
    -- 등록에 쓴 후보의 순위(1~3)
    ADD COLUMN registered_rank      INTEGER,
    ADD COLUMN registered_at        TIMESTAMPTZ;
