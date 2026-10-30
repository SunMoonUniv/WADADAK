package com.wadadak.course.internal.mine;

import java.util.UUID;

/**
 * 코스 수정 · 삭제(B7). 실제 구현 전이라 스텁({@link MyCoursesStub})만 있다.
 */
interface MyCourseEditor {

    /** 이름 · 난이도 · 특징만 바꾼다 */
    MyCourseItem edit(UUID memberId, UUID courseId, EditCourseRequest request);

    /** 공개 중이면 비공개로 바꾸고 24시간 뒤 지운다. 이미 삭제 예정이면 그대로 돌려준다 */
    MyCourseItem delete(UUID memberId, UUID courseId);
}
