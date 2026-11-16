-- 기록 목록(RecordSummary)에 코스 요약(course)을, 기록 상세(Result.course)에 달릴 때의 코스 이름(courseName)을 채운다(MY I1).
-- 새 기록은 처리 때 채운다. 이미 저장된 코스 기록만 고치며, 이름은 준비 때 저장한 코스 시도에서 가져온다.
-- 자유 러닝(course가 null이거나 코스 시도가 없음)은 그대로 둔다. 목록의 course 칸이 없으면 null로 읽힌다.
UPDATE run.records r
SET result_json  = jsonb_set(r.result_json::jsonb, '{course,courseName}', to_jsonb(a.course_name))::text,
    summary_json = jsonb_set(r.summary_json::jsonb, '{course}', jsonb_build_object(
        'courseId', r.result_json::jsonb #> '{course,courseId}',
        'courseName', a.course_name,
        'completed', r.result_json::jsonb #> '{course,completed}',
        'progressPercent', r.result_json::jsonb #> '{course,progressPercent}',
        'reviewEligible', r.result_json::jsonb #> '{course,reviewEligible}'))::text
FROM run.course_attempts a
WHERE a.session_id = r.id
  AND jsonb_typeof(r.result_json::jsonb -> 'course') = 'object';
