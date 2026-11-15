package com.wadadak.notification.internal.inbox;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.response.ApiResult;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/** 알림함 REST API(Figma F3 알림 센터 · A2 종 아이콘). 토큰의 sub가 회원 ID다 */
@RestController
@RequestMapping("/api/v1/notifications")
@RequiredArgsConstructor
class NotificationInboxController {

    private final NotificationInboxService service;

    @Operation(summary = "알림함 (F3)",
            description = "최근 30일 알림을 최신순으로 준다. F4 푸시 알림을 꺼 둔 종류도 여기에는 쌓인다. "
                    + "data는 누르면 열 화면 정보다(만료 임박: type=COURSE_EXPIRING_SOON · courseId → B1). "
                    + "read가 false면 안 읽은 알림이다. 다음 쪽은 nextCursor를 cursor로 보낸다. "
                    + "잘못된 커서 COMMON-001, 탈퇴한 회원 COMMON-002.")
    @GetMapping
    ApiResult<CursorSlice<NotificationItem>> list(@AuthenticationPrincipal Jwt jwt, @ParameterObject @Valid Cursorable page) {
        return ApiResult.success(service.list(memberId(jwt), page));
    }

    @Operation(summary = "안 읽은 알림 수 (A2 종 아이콘 · F3)",
            description = "최근 30일 알림 중 읽지 않은 수. 탈퇴한 회원 COMMON-002.")
    @GetMapping("/unread-count")
    ApiResult<UnreadCount> unreadCount(@AuthenticationPrincipal Jwt jwt) {
        return ApiResult.success(service.unreadCount(memberId(jwt)));
    }

    @Operation(summary = "알림 읽음 (F3 알림 누르기 · 푸시 누르기)",
            description = "그 알림을 읽음으로 바꾼다. 푸시의 data.notificationId를 그대로 보내면 된다. "
                    + "이미 읽었거나 없거나 남의 알림이면 그냥 넘어간다. UUID가 아니면 COMMON-001, 탈퇴한 회원 COMMON-002.")
    @PutMapping("/{notificationId}/read")
    ApiResult<Void> markRead(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID notificationId) {
        service.markRead(memberId(jwt), notificationId);
        return ApiResult.success();
    }

    @Operation(summary = "모두 읽음 (F3)",
            description = "안 읽은 알림을 모두 읽음으로 바꾼다. 탈퇴한 회원 COMMON-002.")
    @PutMapping("/read-all")
    ApiResult<Void> markAllRead(@AuthenticationPrincipal Jwt jwt) {
        service.markAllRead(memberId(jwt));
        return ApiResult.success();
    }

    private static UUID memberId(Jwt jwt) {
        return UUID.fromString(jwt.getSubject());
    }
}
