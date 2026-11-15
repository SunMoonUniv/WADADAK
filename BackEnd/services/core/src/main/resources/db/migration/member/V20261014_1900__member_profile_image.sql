-- 프로필 사진(정책 공통 5: 1장). 파일은 사진 저장소에 두고 키만 저장한다(개발 정책 7장 사진 업로드).
-- 키 하나는 회원 하나만 쓴다. 사진 주소에 키가 보여서 남의 키를 가져다 쓰면, 그 회원이 사진을 바꾸거나 탈퇴할 때 원래 파일이 지워진다.
ALTER TABLE member.members
    ADD COLUMN profile_image_key VARCHAR(100) CHECK (profile_image_key LIKE 'member/%');
CREATE UNIQUE INDEX members_profile_image_key_uk ON member.members (profile_image_key);
