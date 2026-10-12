package com.wadadak.ranking.internal.course;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.member.MemberProfile;
import com.wadadak.ranking.GhostCandidate;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingErrorCode;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 순위가 매겨진 대표 기록으로 응답을 만든다. 실제 구현과 스텁이 같은 규칙을 쓰게 한 곳에 둔다.
 * 수치 처리(정책 D-13): 평균·페이스는 반올림한 정수 초, 상위 비율은 올림한 정수.
 */
final class CourseRankingAssembler {

    static final int TOP_SIZE = 5;

    private CourseRankingAssembler() {
    }

    /**
     * @param ranking          내 정보 공개 회원의 대표 기록, 순위순
     * @param requesterVisible 요청자가 내 정보를 공개하고 있으면 {@code true}
     * @param privateRecord    요청자가 비공개일 때 그 기간 자기 대표 기록. 없으면 {@code null}
     * @param profiles         회원 ID로 표시용 프로필을 찾는다. 못 찾은 회원은 결과에서 빠져도 된다
     */
    static CourseRankingSummary summary(List<RankedRecord> ranking, UUID requesterId, boolean requesterVisible,
                                        RankedRecord privateRecord, Function<Set<UUID>, Map<UUID, MemberProfile>> profiles) {
        List<RankedRecord> top = ranking.subList(0, Math.min(TOP_SIZE, ranking.size()));
        Map<UUID, MemberProfile> found = profiles.apply(memberIds(top));
        Integer average = ranking.isEmpty() ? null
                : (int) Math.round(ranking.stream().mapToInt(RankedRecord::courseElapsedSeconds).average().orElseThrow());
        return new CourseRankingSummary(ranking.size(), average, me(ranking, requesterId, requesterVisible, privateRecord),
                top.stream().map(record -> entry(record, found, requesterId)).toList(),
                ghostCandidates(ranking, requesterId, 1).stream().findFirst().orElse(null));
    }

    static CursorSlice<CourseRankingEntry> entries(List<RankedRecord> ranking, UUID requesterId, Cursorable page,
                                                   Function<Set<UUID>, Map<UUID, MemberProfile>> profiles) {
        CursorSlice<RankedRecord> slice = CursorSlice.ofOffset(ranking, page);
        Map<UUID, MemberProfile> found = profiles.apply(memberIds(slice.content()));
        return slice.map(record -> entry(record, found, requesterId));
    }

    static List<GhostCandidate> ghostCandidates(List<RankedRecord> ranking, UUID requesterId, int limit) {
        if (limit < 1 || limit > RankingApi.MAX_LIMIT) {
            throw new AppException(RankingErrorCode.INVALID_GHOST_LIMIT);
        }
        return ranking.stream()
                .filter(record -> !record.memberId().equals(requesterId))
                .limit(limit)
                .map(record -> new GhostCandidate(record.runRecordId(), record.memberId(), record.rank(),
                        record.courseElapsedSeconds()))
                .toList();
    }

    private static MyCourseRanking me(List<RankedRecord> ranking, UUID requesterId, boolean requesterVisible,
                                      RankedRecord privateRecord) {
        if (!requesterVisible) {
            return privateRecord == null ? new MyCourseRanking(MyCourseRanking.Status.PRIVATE, null, null, null, null, null)
                    : new MyCourseRanking(MyCourseRanking.Status.PRIVATE, null, privateRecord.courseElapsedSeconds(),
                    pace(privateRecord), privateRecord.completedAt(), null);
        }
        return ranking.stream()
                .filter(record -> record.memberId().equals(requesterId))
                .findFirst()
                .map(record -> new MyCourseRanking(MyCourseRanking.Status.RANKED, record.rank(), record.courseElapsedSeconds(),
                        pace(record), record.completedAt(), (int) Math.ceil(record.rank() * 100.0 / ranking.size())))
                .orElse(new MyCourseRanking(MyCourseRanking.Status.NO_RECORD, null, null, null, null, null));
    }

    private static CourseRankingEntry entry(RankedRecord record, Map<UUID, MemberProfile> profiles, UUID requesterId) {
        MemberProfile profile = profiles.get(record.memberId());
        return new CourseRankingEntry(record.rank(), record.memberId(), profile == null ? null : profile.nickname(),
                profile == null ? null : profile.profileImageUrl(), record.courseElapsedSeconds(), pace(record),
                record.completedAt(), record.memberId().equals(requesterId));
    }

    private static int pace(RankedRecord record) {
        return (int) Math.round(record.courseElapsedSeconds() * 1000.0 / record.courseDistanceMeters());
    }

    private static Set<UUID> memberIds(List<RankedRecord> records) {
        return records.stream().map(RankedRecord::memberId).collect(Collectors.toSet());
    }
}
