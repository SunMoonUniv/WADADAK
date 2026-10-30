package com.wadadak.course.internal.mine;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;

import java.util.UUID;

/**
 * 내가 등록한 코스(G4) 목록 · 합계와 코스 수정(B7). 실제 구현은 {@link MyCourseService},
 * {@code app.stub.course-mine: true}면 {@link MyCoursesStub}이 대신한다.
 */
interface MyCourses {

    /** 내가 등록한 공개 중 · 삭제 예정 코스. 만료 임박 코스가 먼저(만료가 가까운 순), 나머지는 최근 등록순 */
    CursorSlice<MyCourseItem> list(UUID memberId, Cursorable page);

    /** 공개 중인 코스만 센다 */
    MyCourseSummary summary(UUID memberId);

    /** 이름 · 난이도 · 특징만 바꾼다. 응답은 바뀐 카드 */
    MyCourseItem edit(UUID memberId, UUID courseId, EditCourseRequest request);
}
