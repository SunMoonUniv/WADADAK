package com.wadadak.notification.internal;

import com.wadadak.event.course.CourseExpiringSoonEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import com.wadadak.notification.internal.delivery.CourseExpiryNotice;
import com.wadadak.notification.internal.delivery.NotificationDraft;
import com.wadadak.notification.internal.delivery.NotificationStore;
import com.wadadak.notification.internal.device.DeviceTokenRepository;
import com.wadadak.notification.internal.setting.NotificationSettingRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Instant;

/**
 * 다른 모듈 이벤트를 받는 곳(개발 정책 5.6). notification은 다른 모듈을 호출하지 않고 이벤트만 받는다.
 * 그래서 나중에 "이벤트만 받는 알림 서비스"로 그대로 떼어낼 수 있다(개발 정책 11.4).
 *
 * <p>[읽는 법] {@code @ApplicationModuleListener} 메서드는 발행한 쪽 트랜잭션이 커밋된 뒤 다른 스레드 · 트랜잭션에서 돈다.
 * 실패하면 아웃박스에 남아 다시 시도된다. 그래서 두 번 와도 결과가 같게 짰다. 메서드 이름은 처리 기록의 키라 바꾸지 않는다.
 *
 * <p>여기서는 알림을 만들기만 하고 보내지 않는다. 보내기는 발송 작업이 따로 한다(네트워크가 이벤트 처리를 붙잡지 않게).
 */
@Slf4j
@Component
@RequiredArgsConstructor
class NotificationEventHandler {

    private final WithdrawnMembers withdrawnMembers;
    private final NotificationSettingRepository settings;
    private final DeviceTokenRepository tokens;
    private final NotificationStore notifications;
    private final Clock clock;

    /**
     * 내 코스 만료 임박(삽입형). 등록자가 탈퇴했거나 보낼 기한이 지났으면 만들지 않는다.
     * `내 코스 만료 임박`(F4 푸시 알림)을 껐으면 알림함에만 남기고 휴대폰에는 보내지 않는다
     * (Figma AD7 "사용자가 F4에서 끈 유형은 알림센터에만 저장").
     * 같은 (코스, 만료 시각, 남은 날)은 알림 유니크로 한 번만 만든다.
     */
    @ApplicationModuleListener
    public void on(CourseExpiringSoonEvent event) {
        Instant now = clock.instant();
        NotificationDraft draft = CourseExpiryNotice.draft(event);
        // 기한이 지난 "7일 뒤 만료돼요"는 날짜가 틀린 말이라 알림함에도 남기지 않는다
        if (!now.isBefore(draft.sendUntil()) || withdrawnMembers.isWithdrawn(event.creatorId())) {
            return;
        }
        boolean push = settings.find(event.creatorId()).courseExpiringSoon();
        if (notifications.enqueue(draft, now, push)) {
            log.info("만료 임박 알림 · 코스 {} D-{} · 푸시 {} · event {}", event.courseId(), event.daysLeft(), push, event.eventId());
        }
    }

    /**
     * 회원 탈퇴(삭제형, 원래 멱등). 탈퇴 표시를 먼저 남겨 이 뒤에 오는 만료 임박 이벤트 · 토큰 등록을 받지 않는다.
     * 알림 · 기기 토큰(보낼 줄 포함) · 설정을 지운다(개발 정책 5.6).
     */
    @ApplicationModuleListener
    public void on(MemberWithdrawnEvent event) {
        withdrawnMembers.mark(event.memberId(), event.withdrawnAt());
        notifications.deleteForMember(event.memberId());
        tokens.deleteForMember(event.memberId());
        settings.deleteForMember(event.memberId());
    }
}
