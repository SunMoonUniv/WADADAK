package com.wadadak.ranking.internal.course;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import com.wadadak.ranking.GhostCandidate;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingPeriod;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 코스 랭킹(F8). 기록은 run의 완주 이벤트로 쌓이고, 순위는 조회할 때 계산한다(정책 공통 6).
 * 숨김·삭제된 코스는 기록이 없는 코스와 같게 돌려준다.
 */
@Slf4j
@Service
@ConditionalOnProperty(name = "app.stub.ranking", havingValue = "false", matchIfMissing = true)
@RequiredArgsConstructor
class CourseRankingService implements RankingApi, CourseRankingReader {

    private final CourseRankingRepository repository;
    private final MemberApi memberApi;
    private final Clock clock;

    @Override
    @Transactional(readOnly = true)
    public List<GhostCandidate> getPublicGhostCandidates(UUID courseId, RankingPeriod period, UUID requesterId, int limit) {
        return CourseRankingAssembler.ghostCandidates(ranking(courseId, from(period)), requesterId, limit);
    }

    @Override
    @Transactional(readOnly = true)
    public CourseRankingSummary summary(UUID courseId, RankingPeriod period, UUID requesterId) {
        Instant from = from(period);
        boolean visible = repository.isVisible(requesterId);
        RankedRecord privateRecord = visible || repository.isHidden(courseId) ? null
                : repository.best(courseId, requesterId, from).orElse(null);
        return CourseRankingAssembler.summary(ranking(courseId, from), requesterId, visible, privateRecord, this::profiles);
    }

    @Override
    @Transactional(readOnly = true)
    public CursorSlice<CourseRankingEntry> entries(UUID courseId, RankingPeriod period, UUID requesterId, Cursorable page) {
        // ponytail: 오프셋 커서라 페이지 사이에 새 기록이 들어오면 한 줄 겹치거나 빠질 수 있다. 문제 되면 (시간, 등록 시각, 기록 ID) 키셋 커서로
        return CourseRankingAssembler.entries(ranking(courseId, from(period)), requesterId, page, this::profiles);
    }

    private List<RankedRecord> ranking(UUID courseId, Instant from) {
        return repository.isHidden(courseId) ? List.of() : repository.ranking(courseId, from);
    }

    /** 기간 시작. 이번 주는 월요일 00:00, 이번 달은 1일 00:00(Asia/Seoul) */
    private Instant from(RankingPeriod period) {
        LocalDate today = LocalDate.now(clock.withZone(TimeConfig.SEOUL));
        return switch (period) {
            case ALL -> Instant.EPOCH;
            case MONTH -> today.withDayOfMonth(1).atStartOfDay(TimeConfig.SEOUL).toInstant();
            case WEEK -> today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)).atStartOfDay(TimeConfig.SEOUL).toInstant();
        };
    }

    /** 표시용이라 실패해도 랭킹은 보여준다. 닉네임·사진만 비운다(개발 정책 4.4). */
    private Map<UUID, MemberProfile> profiles(Set<UUID> memberIds) {
        if (memberIds.isEmpty()) {
            return Map.of();
        }
        try {
            return memberApi.getProfiles(memberIds).stream()
                    .collect(Collectors.toMap(MemberProfile::memberId, Function.identity()));
        } catch (RuntimeException e) {
            log.warn("회원 프로필 조회 실패. 닉네임 없이 랭킹을 돌려준다", e);
            return Map.of();
        }
    }
}
