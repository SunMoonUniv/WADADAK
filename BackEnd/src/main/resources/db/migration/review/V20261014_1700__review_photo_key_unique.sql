-- 사진 키는 리뷰 하나만 쓴다. 사진 주소에 키가 보여서 남의 사진을 가져다 붙이면, 그 리뷰를 지울 때 원래 리뷰의 사진 파일도 지워진다.
ALTER TABLE review.review_photos
    ADD CONSTRAINT review_photos_key_uk UNIQUE (photo_key);
