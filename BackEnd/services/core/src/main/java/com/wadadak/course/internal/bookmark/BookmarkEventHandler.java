package com.wadadak.course.internal.bookmark;

import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.member.MemberWithdrawnEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

/**
 * 코스 삭제가 끝나면 그 코스의 저장을, 회원이 탈퇴하면 그 회원의 저장을 지운다(정책 문서 4.1 `저장한 코스 API`).
 * 지우기만 해서 같은 이벤트를 다시 받아도 결과가 같다. 그래서 처리 기록을 남기지 않는다(개발 정책 5.4).
 */
@Component
@RequiredArgsConstructor
class BookmarkEventHandler {

    private final BookmarkRepository bookmarks;

    /** 삭제 예정(HIDDEN)인 동안은 목록에 남고, 삭제(DELETED)가 끝나면 지운다 */
    @ApplicationModuleListener
    public void on(CourseStatusChangedEvent event) {
        if (event.status() == CourseStatus.DELETED) {
            bookmarks.deleteForCourse(event.courseId());
        }
    }

    @ApplicationModuleListener
    public void on(MemberWithdrawnEvent event) {
        bookmarks.deleteForMember(event.memberId());
    }
}
