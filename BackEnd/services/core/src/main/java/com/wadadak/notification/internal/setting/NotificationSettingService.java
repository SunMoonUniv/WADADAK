package com.wadadak.notification.internal.setting;

import com.wadadak.notification.internal.WithdrawnMembers;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.UUID;

/** 알림 설정 조회 · 변경. 로그인한 본인 것만 다룬다 */
@Service
@RequiredArgsConstructor
class NotificationSettingService {

    private final NotificationSettingRepository settings;
    private final WithdrawnMembers withdrawnMembers;
    private final Clock clock;

    @Transactional(readOnly = true)
    NotificationSettings get(UUID memberId) {
        withdrawnMembers.requireActive(memberId);
        return settings.find(memberId);
    }

    /** 바꾼 뒤의 설정을 돌려준다. 앱은 이 값으로 스위치를 맞춘다 */
    @Transactional
    NotificationSettings change(UUID memberId, NotificationSettings request) {
        withdrawnMembers.requireActive(memberId);
        settings.save(memberId, request, clock.instant());
        return request;
    }
}
