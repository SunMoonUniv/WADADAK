-- ranking이 회원 지역 이력을 받기 전에 가입한 회원. 서버가 뜰 때 가입 때 지역으로 MemberRegionChangedEvent를 다시 보내고 행을 지운다.
CREATE TABLE member.region_event_backfill
(
    member_id UUID NOT NULL PRIMARY KEY REFERENCES member.members (id)
);

INSERT INTO member.region_event_backfill (member_id)
SELECT id
FROM member.members
WHERE status = 'ACTIVE';
