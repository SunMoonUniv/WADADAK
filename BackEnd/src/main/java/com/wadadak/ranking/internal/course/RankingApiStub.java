package com.wadadak.ranking.internal.course;

import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.stub.StubImplementation;
import com.wadadak.member.MemberProfile;
import com.wadadak.ranking.GhostCandidate;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingPeriod;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 랭킹 스텁. 어떤 코스든 아래 고정 기록에 요청자 기록을 끼워 순위를 매긴다. 스텁 코스(약 1km)를 5~6분에 달린 기록이다.
 * 응답은 실제 구현과 같은 {@link CourseRankingAssembler}로 만든다.
 * <ul>
 *     <li>{@code ALL}: 12명, 요청자 5위. 2위·9위가 공동순위</li>
 *     <li>{@code MONTH}: 6명, 요청자 3위</li>
 *     <li>{@code WEEK}: 3명, 1위가 공동순위. 요청자는 기록 없음</li>
 * </ul>
 * 확인용 코스 ID: {@code …0001} → 기록 없음(참여 0명), {@code …0002} → 요청자가 내 정보 비공개.
 */
@Component
@ConditionalOnProperty(name = "app.stub.ranking", havingValue = "true")
class RankingApiStub implements RankingApi, CourseRankingReader, StubImplementation {

    static final UUID NO_RECORD_COURSE_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    static final UUID PRIVATE_COURSE_ID = UUID.fromString("00000000-0000-0000-0000-000000000002");

    /** {@code CourseApiStub}의 코스 거리 */
    private static final int COURSE_DISTANCE_METERS = 1001;
    private static final Instant BASE_TIME = Instant.parse("2026-10-01T00:00:00Z");

    /** 다른 러너의 대표 기록: 회원 번호와 코스 총 소요시간(초) */
    private static final Map<RankingPeriod, List<Run>> OTHERS = Map.of(
            RankingPeriod.ALL, List.of(other(1, 290), other(2, 305), other(3, 305), other(4, 312), other(5, 326),
                    other(6, 334), other(7, 341), other(8, 352), other(9, 352), other(10, 365), other(11, 380)),
            RankingPeriod.MONTH, List.of(other(2, 297), other(4, 309), other(6, 330), other(8, 344), other(10, 371)),
            RankingPeriod.WEEK, List.of(other(3, 301), other(5, 301), other(7, 333)));
    /** 요청자의 대표 기록(초). {@code WEEK}는 없다 */
    private static final Map<RankingPeriod, Integer> MINE = Map.of(RankingPeriod.ALL, 318, RankingPeriod.MONTH, 318);
    private static final Map<UUID, String> NICKNAMES = OTHERS.values().stream().flatMap(List::stream)
            .collect(Collectors.toMap(Run::memberId, Run::nickname, (same, ignored) -> same));

    @Override
    public List<GhostCandidate> getPublicGhostCandidates(UUID courseId, RankingPeriod period, UUID requesterId, int limit) {
        return CourseRankingAssembler.ghostCandidates(ranking(courseId, period, requesterId), requesterId, limit);
    }

    @Override
    public CourseRankingSummary summary(UUID courseId, RankingPeriod period, UUID requesterId) {
        boolean visible = !PRIVATE_COURSE_ID.equals(courseId);
        RankedRecord privateRecord = visible || !MINE.containsKey(period) ? null : mine(requesterId, period).toRecord(0);
        return CourseRankingAssembler.summary(ranking(courseId, period, requesterId), requesterId, visible, privateRecord,
                profiles(requesterId));
    }

    @Override
    public CursorSlice<CourseRankingEntry> entries(UUID courseId, RankingPeriod period, UUID requesterId, Cursorable page) {
        return CourseRankingAssembler.entries(ranking(courseId, period, requesterId), requesterId, page, profiles(requesterId));
    }

    /** 내 정보 비공개 회원은 빼고 코스 총 소요시간 순으로 공동순위를 매긴다(1·2·2·4). */
    private static List<RankedRecord> ranking(UUID courseId, RankingPeriod period, UUID requesterId) {
        if (NO_RECORD_COURSE_ID.equals(courseId)) {
            return List.of();
        }
        List<Run> runs = new ArrayList<>(OTHERS.get(period));
        if (MINE.containsKey(period) && !PRIVATE_COURSE_ID.equals(courseId)) {
            runs.add(mine(requesterId, period));
        }
        runs.sort(Comparator.comparingInt(Run::elapsedSeconds));
        List<RankedRecord> ranking = new ArrayList<>();
        for (int i = 0; i < runs.size(); i++) {
            boolean tie = i > 0 && runs.get(i).elapsedSeconds() == runs.get(i - 1).elapsedSeconds();
            ranking.add(runs.get(i).toRecord(tie ? ranking.get(i - 1).rank() : i + 1));
        }
        return ranking;
    }

    private static Function<Set<UUID>, Map<UUID, MemberProfile>> profiles(UUID requesterId) {
        return memberIds -> memberIds.stream().collect(Collectors.toMap(id -> id, id -> new MemberProfile(id,
                id.equals(requesterId) ? "러너-" + id.toString().substring(0, 4) : NICKNAMES.get(id), null, false)));
    }

    private static Run other(int n, int elapsedSeconds) {
        return new Run(UUID.fromString("00000000-0000-0000-0002-%012d".formatted(n)),
                UUID.fromString("00000000-0000-0000-0001-%012d".formatted(n * 1000 + elapsedSeconds)),
                "러너" + n, elapsedSeconds, BASE_TIME.plus(Duration.ofDays(n)));
    }

    private static Run mine(UUID requesterId, RankingPeriod period) {
        int elapsedSeconds = MINE.get(period);
        return new Run(requesterId, UUID.fromString("00000000-0000-0000-0001-%012d".formatted(elapsedSeconds)), null,
                elapsedSeconds, BASE_TIME);
    }

    private record Run(UUID memberId, UUID runRecordId, String nickname, int elapsedSeconds, Instant completedAt) {

        RankedRecord toRecord(int rank) {
            return new RankedRecord(rank, runRecordId, memberId, elapsedSeconds, COURSE_DISTANCE_METERS, completedAt);
        }
    }
}
