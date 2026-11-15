package com.wadadak.notification.internal.delivery;

import com.wadadak.event.course.CourseExpiringSoonEvent;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;

/**
 * 내 코스 만료 임박 알림(정책 공통 4)의 문구와 보낼 기한. 문구는 구현 값이다(정책 문서에 정해진 문구가 없다).
 *
 * <p>예: 제목 `내 코스 만료 임박`, 본문 `‘한강 야경 코스’ 코스가 7일 뒤 만료돼요.`(D-1은 `내일`)
 */
public final class CourseExpiryNotice {

    /**
     * 오전 9시 알림을 늦어도 12시간 안에만 보낸다. 그보다 늦게 보내면 날짜가 바뀌어 "7일 뒤"가 틀린 말이 될 수 있다.
     * 정책도 "그 시각에 서버가 꺼져 있었으면 그날 알림은 다시 보내지 않는다"다.
     */
    static final Duration SEND_WITHIN = Duration.ofHours(12);

    private CourseExpiryNotice() {
    }

    public static NotificationDraft draft(CourseExpiringSoonEvent event) {
        String when = switch (event.daysLeft()) {
            case 0 -> "오늘";
            case 1 -> "내일";
            default -> event.daysLeft() + "일 뒤";
        };
        Instant sendUntil = event.occurredAt().plus(SEND_WITHIN);
        if (sendUntil.isAfter(event.expiresAt())) {
            sendUntil = event.expiresAt(); // 만료된 코스는 알릴 의미가 없다
        }
        return new NotificationDraft(event.creatorId(), NotificationKind.COURSE_EXPIRING_SOON,
                // 같은 (코스, 만료 시각, 남은 날)은 한 번만(개발 정책 5.6). 완주로 연장되면 만료 시각이 바뀌어 다시 알릴 수 있다
                event.courseId() + "/" + event.expiresAt() + "/" + event.daysLeft(),
                "내 코스 만료 임박",
                "‘" + event.courseName() + "’ 코스가 " + when + " 만료돼요.",
                Map.of("type", NotificationKind.COURSE_EXPIRING_SOON.name(), "courseId", event.courseId().toString()),
                sendUntil);
    }
}
