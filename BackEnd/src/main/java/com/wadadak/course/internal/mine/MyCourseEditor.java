package com.wadadak.course.internal.mine;

import java.util.UUID;

/**
 * 코스 삭제(B7). 실제 구현 전이라 스텁({@link MyCoursesStub})만 있다. 실제 구현 PR에서 {@link MyCourses}로 옮긴다.
 */
interface MyCourseEditor {

    /** 공개 중이면 비공개로 바꾸고 24시간 뒤 지운다. 이미 삭제 예정이면 그대로 돌려준다 */
    MyCourseItem delete(UUID memberId, UUID courseId);
}
