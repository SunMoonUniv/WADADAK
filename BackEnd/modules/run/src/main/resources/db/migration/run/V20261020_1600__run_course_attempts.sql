-- 코스 러닝 시도(F6 B단계). 세션 하나에 코스 하나.
-- 준비(코스 스냅샷)는 측정 시작 전이라 run.sessions 행이 아직 없어 FK를 두지 않는다. 기록 삭제·탈퇴 때 함께 지운다.
CREATE TABLE run.course_attempts (
    session_id uuid PRIMARY KEY,
    member_id uuid NOT NULL,
    course_id uuid NOT NULL,
    course_name varchar(50) NOT NULL,
    course_version bigint NOT NULL,
    -- 판정용 기준 경로 스냅샷(GeoPoint JSON 배열). 시작 뒤 코스가 바뀌어도 이 경로로 판정한다(CourseApi)
    route_json text NOT NULL,
    total_distance_meters integer NOT NULL,
    -- 측정 시작(시작 신호). null이면 준비만 했다
    started_at timestamptz,
    -- CourseRunStartedEvent.occurredAt. 기록 삭제 때 RunRecordDeletedEvent.startedAt으로 보낸다
    started_event_at timestamptz,
    -- 현재 러너 수에서 뺀 시각과 이유(SEGMENT_END · UPLOAD · TIMEOUT · DELETED)
    released_at timestamptz,
    release_reason varchar(20),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX run_course_attempts_member ON run.course_attempts(member_id);
CREATE INDEX run_course_attempts_active ON run.course_attempts(course_id) WHERE started_at IS NOT NULL AND released_at IS NULL;
CREATE INDEX run_course_attempts_expiring ON run.course_attempts(started_at) WHERE started_at IS NOT NULL AND released_at IS NULL;

-- 코스별 현재 러너 수 이벤트 version. 같은 행을 잠가 같은 코스의 증감을 한 줄로 세운다
CREATE TABLE run.course_runner_counts (
    course_id uuid PRIMARY KEY,
    version bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
