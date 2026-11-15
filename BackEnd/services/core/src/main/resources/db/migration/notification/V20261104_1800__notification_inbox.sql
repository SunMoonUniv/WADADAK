-- 알림함(Figma F3 알림 센터). 앱이 최근 30일 알림을 최신순으로 보이고, 읽은 알림은 파란 점을 지운다.

-- 읽은 시각. 비어 있으면 아직 읽지 않았다
ALTER TABLE notification.notifications ADD COLUMN read_at TIMESTAMPTZ;

-- 목록(회원의 알림을 최신순) · 안 읽은 수 · 탈퇴 때 지우기. (member_id)만 있던 인덱스를 대신한다(앞 칸이 같아 탈퇴 때도 쓴다)
DROP INDEX notification.notifications_member_id_idx;
CREATE INDEX notifications_member_id_created_at_idx ON notification.notifications (member_id, created_at DESC, id DESC);
