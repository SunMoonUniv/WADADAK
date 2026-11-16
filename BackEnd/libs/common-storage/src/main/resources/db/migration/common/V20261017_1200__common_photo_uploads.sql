-- 업로드 폼을 받고 아직 리뷰·가입에 저장하지 않은 사진(개발 정책 7장 사진 업로드, PhotoUploads).
-- 앱이 저장소에 직접 올려서 서버는 업로드를 보지 못한다. 폼을 줄 때 적고, 저장하면 지운다. 남은 줄은 버려진 사진이다.
-- owner: 폼을 받은 사람. 회원 ID, 가입 전에는 '{소셜 제공자}:{소셜 ID}'. 이 값으로 발급 횟수를 센다.
CREATE TABLE common.photo_uploads
(
    photo_key  VARCHAR(100) NOT NULL,
    owner      VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL,
    PRIMARY KEY (photo_key)
);
CREATE INDEX photo_uploads_owner_idx ON common.photo_uploads (owner, created_at);
CREATE INDEX photo_uploads_created_at_idx ON common.photo_uploads (created_at);
