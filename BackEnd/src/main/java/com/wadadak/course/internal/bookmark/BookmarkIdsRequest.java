package com.wadadak.course.internal.bookmark;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * 저장 해제 · 저장 여부를 물을 코스들. 같은 ID를 여러 번 보내도 한 번으로 본다.
 *
 * @param courseIds 1 ~ {@value #MAX}개
 */
record BookmarkIdsRequest(@NotEmpty @Size(max = MAX) List<UUID> courseIds) {

    /** 한 번에 보낼 수 있는 코스 수(현재 러너 수 일괄 조회와 같다) */
    static final int MAX = 100;

    Set<UUID> ids() {
        return new LinkedHashSet<>(courseIds);
    }
}
