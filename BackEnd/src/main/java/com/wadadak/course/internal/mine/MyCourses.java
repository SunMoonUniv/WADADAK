package com.wadadak.course.internal.mine;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;

import java.util.UUID;

/**
 * 내 코스 관리(G4 내가 등록한 코스 · B7 코스 수정). 실제 구현 전이라 스텁({@link MyCoursesStub})만 있다.
 */
interface MyCourses {

    /** 내가 등록한 공개 중 · 삭제 예정 코스. 만료 임박 코스가 먼저(만료가 가까운 순), 나머지는 최근 등록순 */
    CursorSlice<MyCourseItem> list(UUID memberId, Cursorable page);

    MyCourseSummary summary(UUID memberId);

    /** 이름 · 난이도 · 특징만 바꾼다 */
    MyCourseItem edit(UUID memberId, UUID courseId, EditCourseRequest request);

    /** 공개 중이면 비공개로 바꾸고 24시간 뒤 지운다. 이미 삭제 예정이면 그대로 돌려준다 */
    MyCourseItem delete(UUID memberId, UUID courseId);
}
