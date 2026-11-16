-- 기록 삭제(RunRecordDeletedEvent)가 주행 기록(RunSessionEndedEvent)보다 먼저 처리되면 삭제 표시 행을 먼저 만든다.
-- 삭제 이벤트에는 리뷰 자격·진행도·코스 거리가 없어서 비워 둔다. 주행 기록이 나중에 오면 채우고, 삭제 표시는 그대로 둔다.
-- 읽는 쪽은 모두 NOT deleted 행만 보므로 비어 있는 값을 만나지 않는다.
ALTER TABLE review.course_run_records
    ALTER COLUMN review_eligible DROP NOT NULL,
    ALTER COLUMN progress_percent DROP NOT NULL,
    ALTER COLUMN course_distance_meters DROP NOT NULL;
