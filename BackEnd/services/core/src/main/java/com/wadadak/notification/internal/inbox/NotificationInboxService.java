package com.wadadak.notification.internal.inbox;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.notification.internal.WithdrawnMembers;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 알림함(Figma F3 알림 센터). 로그인한 본인의 최근 30일 알림만 다룬다.
 * 탈퇴한 회원은 남은 액세스 토큰으로 와도 받지 않는다(COMMON-002, 알림 설정과 같다).
 */
@Service
@RequiredArgsConstructor
class NotificationInboxService {

    /** 알림함에 보이는 기간(F3 `최근 30일`). 이보다 오래된 알림은 하루 한 번 지운다({@link NotificationRetentionScheduler}) */
    static final Duration KEEP_FOR = Duration.ofDays(30);

    private final NotificationInboxRepository repository;
    private final WithdrawnMembers withdrawnMembers;
    private final Clock clock;

    /** 최신순 한 쪽. 다음 쪽이 있는지 보려고 하나 더 읽는다(course 저장한 코스 목록과 같은 오프셋 커서) */
    @Transactional(readOnly = true)
    CursorSlice<NotificationItem> list(UUID memberId, Cursorable page) {
        withdrawnMembers.requireActive(memberId);
        int offset = page.offset();
        List<NotificationItem> rows = repository.list(memberId, since(), offset, page.size() + 1);
        if (rows.size() <= page.size()) {
            return new CursorSlice<>(rows, null);
        }
        return new CursorSlice<>(rows.subList(0, page.size()), String.valueOf(offset + page.size()));
    }

    @Transactional(readOnly = true)
    UnreadCount unreadCount(UUID memberId) {
        withdrawnMembers.requireActive(memberId);
        return new UnreadCount(repository.unreadCount(memberId, since()));
    }

    /** 없거나 남의 알림이면 그냥 넘어간다(앱이 지워진 알림의 푸시를 눌러도 오류를 보이지 않게) */
    @Transactional
    void markRead(UUID memberId, UUID notificationId) {
        withdrawnMembers.requireActive(memberId);
        repository.markRead(memberId, notificationId, clock.instant());
    }

    @Transactional
    void markAllRead(UUID memberId) {
        withdrawnMembers.requireActive(memberId);
        repository.markAllRead(memberId, clock.instant());
    }

    private Instant since() {
        return clock.instant().minus(KEEP_FOR);
    }
}
