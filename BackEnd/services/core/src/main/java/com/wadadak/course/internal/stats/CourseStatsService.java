package com.wadadak.course.internal.stats;

import com.wadadak.common.config.TimeConfig;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.util.UUID;

/** 코스 상세(조회 수 · 평균 페이스 · 현재 러너)와 만료 배치(삭제)가 쓰는 코스 통계(F11). */
@Service
@RequiredArgsConstructor
public class CourseStatsService {

    private final CourseStatsRepository stats;
    private final Clock clock;

    /** 코스 상세(B1)를 열 때마다 조회 수를 1 늘린다(인기순 2차 기준, FIL-01). 공개 중인 코스만 센다 */
    @Transactional
    public void recordView(UUID courseId) {
        if (stats.lockIfActive(courseId)) {
            stats.addView(courseId, LocalDate.now(clock.withZone(TimeConfig.SEOUL)));
        }
    }

    /**
     * 코스 평균 페이스(초/km, 정수로 반올림). 모든 완주의 코스 완주 페이스 평균이다(정책 공통 2 용어).
     * 경로는 바꿀 수 없어 완주마다 거리가 코스 거리와 같으므로, 소요시간 합 ÷ 완주 수 ÷ 코스 거리로 센다.
     *
     * @return 완주가 없으면 {@code null}
     */
    @Transactional(readOnly = true)
    public Integer averagePaceSecondsPerKm(UUID courseId, int distanceMeters) {
        return stats.completions(courseId)
                .filter(completions -> completions.count() > 0 && completions.seconds() > 0)
                .map(completions -> (int) Math.round(completions.seconds() * 1000.0 / completions.count() / distanceMeters))
                .orElse(null);
    }

    /** 지금 그 코스를 달리는 러너 수(B1-01 현재 러너). run이 보낸 마지막 값이고, 받은 적이 없으면 0이다 */
    @Transactional(readOnly = true)
    public int activeRunners(UUID courseId) {
        return stats.activeRunners(courseId);
    }

    /** 코스가 삭제(DELETED)되면 그 코스의 누적 · 일별 통계와 현재 러너 수를 지운다(개발 정책 6.2). 상태를 바꾸는 트랜잭션 안에서 부른다 */
    @Transactional
    public void deleteFor(UUID courseId) {
        stats.delete(courseId);
    }
}
