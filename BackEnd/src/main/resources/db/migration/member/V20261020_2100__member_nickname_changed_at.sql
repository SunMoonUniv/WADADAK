-- 닉네임은 30일에 한 번 바꿀 수 있다(MY F6 프로필 편집). 마지막으로 바꾼 시각을 남긴다.
-- 가입 때 정한 닉네임은 바꾼 것으로 치지 않아 NULL이다(가입 뒤 첫 변경은 바로 할 수 있다).
ALTER TABLE member.members
    ADD COLUMN nickname_changed_at TIMESTAMPTZ;
