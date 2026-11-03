CREATE SCHEMA notification;

-- 기기 푸시 토큰(FCM 등록 토큰). 앱이 로그인 · 실행할 때마다 다시 등록하고, 로그아웃할 때 지운다.
-- 토큰 하나는 기기 하나다. 같은 기기에 다른 계정이 로그인하면 그 계정으로 옮긴다(유니크 토큰).
CREATE TABLE notification.device_tokens
(
    id         UUID          NOT NULL PRIMARY KEY,
    -- member 모듈의 회원 ID. 다른 스키마라 FK는 없다
    member_id  UUID          NOT NULL,
    token      VARCHAR(1024) NOT NULL,
    platform   VARCHAR(10)   NOT NULL CHECK (platform IN ('ANDROID', 'IOS')),
    created_at TIMESTAMPTZ   NOT NULL,
    -- 마지막으로 등록한 시각. 한 회원에 기기 10개까지 두고 오래된 것부터 지운다
    updated_at TIMESTAMPTZ   NOT NULL,
    CONSTRAINT device_tokens_token_uk UNIQUE (token)
);
-- 회원의 기기 찾기(알림 만들 때 · 10개 넘는 기기 정리 · 탈퇴)
CREATE INDEX device_tokens_member_id_idx ON notification.device_tokens (member_id, updated_at DESC);

-- 알림 설정(F4). 행이 없으면 모두 켜져 있다. 끄거나 다시 켜면 행이 생긴다.
CREATE TABLE notification.notification_settings
(
    member_id            UUID        NOT NULL PRIMARY KEY,
    -- `내 코스 만료 임박`(정책 공통 4)
    course_expiring_soon BOOLEAN     NOT NULL,
    created_at           TIMESTAMPTZ NOT NULL,
    updated_at           TIMESTAMPTZ NOT NULL
);

-- 알림(발송 기록). 회원에게 보낼 알림 한 건이다. 같은 일로는 한 번만 만든다(개발 정책 5.4 삽입형).
-- 예: 만료 임박은 (코스, 만료 시각, 남은 날)마다 한 번. 문구는 만들 때 정해 둔다.
CREATE TABLE notification.notifications
(
    id         UUID         NOT NULL PRIMARY KEY,
    member_id  UUID         NOT NULL,
    kind       VARCHAR(40)  NOT NULL CHECK (kind IN ('COURSE_EXPIRING_SOON')),
    dedupe_key VARCHAR(200) NOT NULL,
    title      VARCHAR(100) NOT NULL,
    body       VARCHAR(300) NOT NULL,
    -- 앱이 알림을 눌렀을 때 열 화면 정보(FCM data, 값은 모두 문자열). 예: {"type": "COURSE_EXPIRING_SOON", "courseId": "..."}
    data       JSONB        NOT NULL,
    -- 이 시각까지 못 보내면 보내지 않는다. 늦게 온 "7일 뒤 만료돼요"는 틀린 말이 된다
    send_until TIMESTAMPTZ  NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL,
    updated_at TIMESTAMPTZ  NOT NULL,
    CONSTRAINT notifications_kind_dedupe_key_uk UNIQUE (kind, dedupe_key)
);
-- 탈퇴한 회원의 알림 지우기
CREATE INDEX notifications_member_id_idx ON notification.notifications (member_id);

-- 기기별 발송. 알림 한 건 × 그 회원의 기기마다 한 줄이다. 발송 작업(PushDispatcher)이 PENDING을 보내고 결과를 적는다.
-- 기기마다 따로 적어서, 한 기기만 실패해 다시 보낼 때 이미 받은 기기에는 또 보내지 않는다.
CREATE TABLE notification.deliveries
(
    notification_id UUID        NOT NULL REFERENCES notification.notifications (id) ON DELETE CASCADE,
    -- 토큰이 지워지면(로그아웃 · 만료된 토큰 · 탈퇴) 그 기기에 보낼 줄도 지운다
    device_token_id UUID        NOT NULL REFERENCES notification.device_tokens (id) ON DELETE CASCADE,
    status          VARCHAR(10) NOT NULL CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'EXPIRED')),
    attempts        SMALLINT    NOT NULL CHECK (attempts >= 0),
    -- 다음에 보낼 시각. 실패하면 조금씩 늦춘다(1분 · 2분 · 4분 … 30분까지)
    next_attempt_at TIMESTAMPTZ NOT NULL,
    last_error      VARCHAR(200),
    sent_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL,
    updated_at      TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (notification_id, device_token_id)
);
-- 보낼 줄 찾기(보낼 시각이 된 PENDING만)
CREATE INDEX deliveries_pending_idx ON notification.deliveries (next_attempt_at) WHERE status = 'PENDING';
-- 토큰을 지울 때 CASCADE가 찾는다
CREATE INDEX deliveries_device_token_id_idx ON notification.deliveries (device_token_id);

-- 탈퇴 회원(MemberWithdrawnEvent). 탈퇴 뒤에 늦게 온 만료 임박 이벤트 · 토큰 등록을 받지 않는다.
-- 등록한 코스는 탈퇴해도 남아 만료 임박 이벤트가 계속 올 수 있다(정책 공통 4).
CREATE TABLE notification.withdrawn_members
(
    member_id    UUID        NOT NULL PRIMARY KEY,
    withdrawn_at TIMESTAMPTZ NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL,
    updated_at   TIMESTAMPTZ NOT NULL
);
