package com.wadadak.course.internal.explore;

import java.util.UUID;

/**
 * 코스 하나의 현재 러너 수(공통 7 · HCR-05 홈 1분 갱신).
 *
 * @param activeRunners 지금 그 코스를 달리는 러너 수. 카드의 {@code activeRunners}와 같다. run이 보낸 마지막 값이고, 받은 적이 없으면 0
 */
record CourseActiveRunners(UUID courseId, int activeRunners) {
}
