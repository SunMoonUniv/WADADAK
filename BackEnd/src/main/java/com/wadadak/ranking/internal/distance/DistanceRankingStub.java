package com.wadadak.ranking.internal.distance;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.region.Region;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.common.stub.StubImplementation;
import com.wadadak.member.MemberProfile;
import com.wadadak.ranking.RankingPeriod;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * 누적 거리 랭킹 스텁({@code app.stub.ranking: true}). 피그마 E1·I5의 기록에 요청자를 끼워 순위를 매긴다.
 * <ul>
 *     <li>전체 랭킹: 누적 31명 중 요청자 26위(128km, 공동순위), 이번 달 21명, 이번 주 16명 중 12위</li>
 *     <li>지역 주간: 요청자의 활동 지역은 서울 성북구로 둔다. 성북구는 16명 중 요청자 12위(지난주 19위),
 *     다른 시·군·구는 요청자 없이 같은 기록이다</li>
 * </ul>
 */
@Component
@ConditionalOnProperty(name = "app.stub.ranking", havingValue = "true")
@RequiredArgsConstructor
class DistanceRankingStub implements DistanceRankingReader, StubImplementation {

    static final String MY_REGION_CODE = "1129000000";

    private static final int TOP_SIZE = 3;
    private static final int REGION_TOP_SIZE = 5;
    private static final int WEEKS_SINCE_FIRST_RECORD = 24;
    private static final int MY_LAST_WEEK_RANK = 19;
    private static final List<String> NAMES = List.of("러너_하늘", "러너_민", "성북러너", "달리는곰", "한강러버", "새벽러닝", "러너_지수", "밤길러너");
    private static final double[] ALL_KM = {1284, 1102, 987, 912, 876, 841, 803, 770, 742, 705, 664, 630, 598, 560, 525,
            490, 452, 418, 380, 341, 305, 268, 230, 196, 160, 128, 95, 61, 40, 22};
    private static final double[] MONTH_KM = {182, 160, 151, 140, 133, 120, 112, 98, 87, 80, 72, 66, 58, 51, 44, 39, 33, 28, 21, 15};
    private static final double[] WEEK_KM = {102.4, 69.8, 66.2, 81.6, 74.0, 88.1, 60.1, 63.5, 57.3, 54.0, 50.6, 45.0, 41.2, 38.9, 30.2};
    private static final Map<RankingPeriod, double[]> OTHERS_KM = Map.of(RankingPeriod.ALL, ALL_KM, RankingPeriod.MONTH, MONTH_KM,
            RankingPeriod.WEEK, WEEK_KM);
    private static final Map<RankingPeriod, Double> MINE_KM = Map.of(RankingPeriod.ALL, 128.0, RankingPeriod.MONTH, 96.4,
            RankingPeriod.WEEK, 48.2);
    private static final double[] G7_WEEK_KM = {32, 24, 15};

    private final RegionDirectory regions;
    private final Clock clock;

    @Override
    public DistanceRankingSummary summary(RankingPeriod period, UUID requesterId) {
        List<Ranked> ranking = ranking(OTHERS_KM.get(period), requesterId, MINE_KM.get(period));
        Ranked mine = ranking.stream().filter(ranked -> ranked.memberId().equals(requesterId)).findFirst().orElseThrow();
        MyDistanceRanking me = new MyDistanceRanking(MyDistanceRanking.Status.RANKED, mine.rank(), mine.meters(),
                meters(MINE_KM.get(RankingPeriod.WEEK)), mine.runCount(), (int) Math.ceil(mine.rank() * 100.0 / ranking.size()), null)
                .withProfile(myProfile(requesterId));
        return new DistanceRankingSummary(ranking.size(), calculatedAt(), me, top(ranking, TOP_SIZE, requesterId),
                ranking.size() > TOP_SIZE ? String.valueOf(TOP_SIZE) : null);
    }

    @Override
    public CursorSlice<DistanceRankingEntry> entries(RankingPeriod period, UUID requesterId, Cursorable page) {
        return CursorSlice.ofOffset(ranking(OTHERS_KM.get(period), requesterId, MINE_KM.get(period)), page)
                .map(ranked -> ranked.toEntry(requesterId));
    }

    @Override
    public RegionWeeklyRanking regionWeekly(Region region, UUID requesterId) {
        Region shown = region != null ? region : regions.findSigungu(MY_REGION_CODE).orElseThrow();
        boolean myRegion = shown.code().equals(MY_REGION_CODE);
        List<Ranked> ranking = ranking(WEEK_KM, requesterId, myRegion ? MINE_KM.get(RankingPeriod.WEEK) : null);
        MyDistanceRanking me = ranking.stream()
                .filter(ranked -> ranked.memberId().equals(requesterId))
                .findFirst()
                .map(mine -> new MyDistanceRanking(MyDistanceRanking.Status.RANKED, mine.rank(), mine.meters(), null,
                        mine.runCount(), null, MY_LAST_WEEK_RANK))
                .orElse(new MyDistanceRanking(MyDistanceRanking.Status.OTHER_REGION, null, null, null, null, null, null))
                .withProfile(myProfile(requesterId));
        LocalDate today = LocalDate.now(clock.withZone(TimeConfig.SEOUL));
        return new RegionWeeklyRanking(shown, today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)), calculatedAt(),
                ranking.size(), me, top(ranking, REGION_TOP_SIZE, requesterId),
                ranking.size() > REGION_TOP_SIZE ? String.valueOf(REGION_TOP_SIZE) : null);
    }

    @Override
    public CursorSlice<DistanceRankingEntry> regionWeeklyEntries(Region region, UUID requesterId, Cursorable page) {
        boolean myRegion = region == null || region.code().equals(MY_REGION_CODE);
        return CursorSlice.ofOffset(ranking(WEEK_KM, requesterId, myRegion ? MINE_KM.get(RankingPeriod.WEEK) : null), page)
                .map(ranked -> ranked.toEntry(requesterId));
    }

    /** 요청자는 전체 랭킹의 이번 주 내 거리, 다른 회원은 피그마 G7의 32 · 24 · 15km 중 하나(ID로 고정) */
    @Override
    public List<MemberWeekDistance> weekDistances(Set<UUID> memberIds, UUID requesterId) {
        return memberIds.stream().map(id -> {
            double km = id.equals(requesterId) ? MINE_KM.get(RankingPeriod.WEEK)
                    : G7_WEEK_KM[Math.floorMod(id.hashCode(), G7_WEEK_KM.length)];
            return new MemberWeekDistance(id, meters(km));
        }).toList();
    }

    /** 거리 순으로 공동순위를 매긴다(1·2·2·4). 같은 거리면 먼저 넣은 러너가 앞이다. */
    private static List<Ranked> ranking(double[] othersKm, UUID requesterId, Double mineKm) {
        List<Ranked> runners = new ArrayList<>();
        for (int i = 0; i < othersKm.length; i++) {
            String name = i < NAMES.size() ? NAMES.get(i) : "러너" + (i + 1);
            runners.add(new Ranked(0, UUID.nameUUIDFromBytes(name.getBytes(StandardCharsets.UTF_8)), name,
                    meters(othersKm[i]), weeklyAverage(ALL_KM[i])));
        }
        if (mineKm != null) {
            runners.add(new Ranked(0, requesterId, myProfile(requesterId).nickname(), meters(mineKm),
                    weeklyAverage(MINE_KM.get(RankingPeriod.ALL))));
        }
        runners.sort(Comparator.comparingInt(Ranked::meters).reversed());
        List<Ranked> ranking = new ArrayList<>();
        for (int i = 0; i < runners.size(); i++) {
            boolean tie = i > 0 && runners.get(i).meters() == runners.get(i - 1).meters();
            ranking.add(runners.get(i).withRank(tie ? ranking.get(i - 1).rank() : i + 1));
        }
        return ranking;
    }

    private static MemberProfile myProfile(UUID requesterId) {
        return new MemberProfile(requesterId, "러너-" + requesterId.toString().substring(0, 4), null, false);
    }

    private static List<DistanceRankingEntry> top(List<Ranked> ranking, int size, UUID requesterId) {
        return ranking.stream().limit(size).map(ranked -> ranked.toEntry(requesterId)).toList();
    }

    private Instant calculatedAt() {
        return LocalDate.now(clock.withZone(TimeConfig.SEOUL)).atStartOfDay(TimeConfig.SEOUL).toInstant();
    }

    private static int meters(double km) {
        return (int) Math.round(km * 1000);
    }

    private static int weeklyAverage(double allKm) {
        return (int) Math.round(allKm * 1000 / WEEKS_SINCE_FIRST_RECORD);
    }

    private record Ranked(int rank, UUID memberId, String nickname, int meters, int weeklyAverageMeters) {

        Ranked withRank(int rank) {
            return new Ranked(rank, memberId, nickname, meters, weeklyAverageMeters);
        }

        /** 스텁은 7km에 한 번 달렸다고 친다 */
        int runCount() {
            return Math.max(1, Math.round(meters / 7000f));
        }

        DistanceRankingEntry toEntry(UUID requesterId) {
            return new DistanceRankingEntry(rank, memberId, nickname, null, meters, runCount(), weeklyAverageMeters,
                    memberId.equals(requesterId));
        }
    }
}
