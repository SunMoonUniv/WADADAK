-- 회원 활동 지역 이력. 지역 주간 랭킹은 그 주 월요일 00:00(Asia/Seoul)에 회원이 있던 지역으로 회원을 묶는다(정책 공통 6).
-- MemberRegionChangedEvent 하나가 한 행이다. (회원, 버전)이 PK라 같은 이벤트가 다시 오거나 순서가 바뀌어 와도 결과가 같다.
-- 어느 주의 지역은 effective_from이 그 주 월요일 이하인 행 중 effective_from이 가장 늦은 행(같으면 버전이 큰 행)이다.
CREATE TABLE ranking.member_region_history
(
    member_id      UUID        NOT NULL,
    -- 회원 엔티티의 @Version
    source_version BIGINT      NOT NULL,
    -- 활동 지역(시·군·구) 법정동 코드
    region_code    VARCHAR(10) NOT NULL,
    -- 이 지역 랭킹에 들어가는 첫 주의 월요일 00:00. 가입 때 지역은 가입한 주, 바꾼 지역은 바꾼 다음 주
    effective_from TIMESTAMPTZ NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (member_id, source_version)
);
