package com.wadadak.ranking.internal.distance;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.region.Region;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import com.wadadak.ranking.RankingErrorCode;
import com.wadadak.ranking.RankingPeriod;
import com.wadadak.ranking.internal.MemberProfiles;
import com.wadadak.ranking.internal.distance.DistanceRankingRepository.MemberDistance;
import com.wadadak.ranking.internal.distance.DistanceRankingRepository.MemberTotal;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * 누적 거리 랭킹(F12). 기록은 run의 등록 이벤트로 쌓이고, 순위는 조회할 때 오늘 00:00(Asia/Seoul) 전에 등록된 기록으로 매긴다.
 * 그래서 순위와 거리는 하루 동안 자정 기준 값이다(정책 공통 6). 자정 뒤에 지운 기록·탈퇴·내 정보 비공개는 바로 빠진다.
 * 같은 거리(m 정수)는 공동순위이고(1·2·2·4), 같은 순위 안에서는 회원 ID순이라 페이지를 넘겨도 순서가 같다.
 * ponytail: 요청마다 그 기간 회원 전체를 읽어 순위를 매긴다. 회원이 많아 느려지면 자정에 순위를 저장해 두고 읽는다
 */
@Service
@ConditionalOnProperty(name = "app.stub.ranking", havingValue = "false", matchIfMissing = true)
@RequiredArgsConstructor
class DistanceRankingService implements DistanceRankingReader {

    static final int TOP_SIZE = 3;
    static final int REGION_TOP_SIZE = 5;

    private static final MyDistanceRanking NO_RECORD =
            new MyDistanceRanking(MyDistanceRanking.Status.NO_RECORD, null, null, null, null, null, null);
    private static final MyDistanceRanking OTHER_REGION =
            new MyDistanceRanking(MyDistanceRanking.Status.OTHER_REGION, null, null, null, null, null, null);

    private final DistanceRankingRepository repository;
    private final RegionDirectory regions;
    private final MemberApi memberApi;
    private final Clock clock;

    @Override
    @Transactional(readOnly = true)
    public DistanceRankingSummary summary(RankingPeriod period, UUID requesterId) {
        Day day = today();
        List<MemberDistance> rows = repository.distances(day.from(period), day.cutoff(), day.weekStart(), null, null);
        List<Ranked> ranking = rank(rows);
        MyDistanceRanking me = mine(rows, requesterId).map(mine -> {
            int thisWeek = (int) Math.round(mine.weekMeters());
            if (!mine.visible()) {
                return new MyDistanceRanking(MyDistanceRanking.Status.PRIVATE, null, mine.meters(), thisWeek,
                        mine.periodRuns(), null, null);
            }
            int rank = rankOf(ranking, requesterId);
            return new MyDistanceRanking(MyDistanceRanking.Status.RANKED, rank, mine.meters(), thisWeek, mine.periodRuns(),
                    (int) Math.ceil(rank * 100.0 / ranking.size()), null);
        }).orElse(NO_RECORD);
        return new DistanceRankingSummary(ranking.size(), day.cutoff(), me.withProfile(myProfile(requesterId)),
                top(ranking, TOP_SIZE, requesterId, day), nextCursor(ranking, TOP_SIZE));
    }

    @Override
    @Transactional(readOnly = true)
    public CursorSlice<DistanceRankingEntry> entries(RankingPeriod period, UUID requesterId, Cursorable page) {
        Day day = today();
        return page(rank(repository.distances(day.from(period), day.cutoff(), day.weekStart(), null, null)), page,
                requesterId, day);
    }

    @Override
    @Transactional(readOnly = true)
    public RegionWeeklyRanking regionWeekly(Region region, UUID requesterId) {
        Day day = today();
        String myRegion = repository.regionAt(requesterId, day.weekStart()).orElse(null);
        Region shown = region != null ? region : region(myRegion);
        List<MemberDistance> rows = regionWeek(day, shown);
        List<Ranked> ranking = rank(rows);
        MyDistanceRanking me = shown.code().equals(myRegion) ? regionMe(day, shown, rows, ranking, requesterId) : OTHER_REGION;
        return new RegionWeeklyRanking(shown, day.monday(), day.cutoff(), ranking.size(), me.withProfile(myProfile(requesterId)),
                top(ranking, REGION_TOP_SIZE, requesterId, day), nextCursor(ranking, REGION_TOP_SIZE));
    }

    @Override
    @Transactional(readOnly = true)
    public CursorSlice<DistanceRankingEntry> regionWeeklyEntries(Region region, UUID requesterId, Cursorable page) {
        Day day = today();
        Region shown = region != null ? region : region(repository.regionAt(requesterId, day.weekStart()).orElse(null));
        return page(rank(regionWeek(day, shown)), page, requesterId, day);
    }

    /** 전체 랭킹의 이번 주 내 거리와 같은 기준(이번 주 월요일 00:00 ~ 오늘 00:00 등록)이다. 비공개 회원은 본인에게만 보인다 */
    @Override
    @Transactional(readOnly = true)
    public List<MemberWeekDistance> weekDistances(Set<UUID> memberIds, UUID requesterId) {
        if (memberIds.isEmpty()) {
            return List.of();
        }
        Day day = today();
        Map<UUID, Double> meters = repository.distancesOf(memberIds, day.weekStart(), day.cutoff());
        Set<UUID> hidden = repository.hiddenOf(memberIds);
        return memberIds.stream().map(id -> {
            if (hidden.contains(id) && !id.equals(requesterId)) {
                return new MemberWeekDistance(id, null);
            }
            return new MemberWeekDistance(id, (int) Math.round(meters.getOrDefault(id, 0.0)));
        }).toList();
    }

    /** 전체 랭킹 누적(ALL)과 같은 기준(오늘 00:00 전 등록)이다. 비공개 회원은 본인에게만 보인다 */
    @Override
    @Transactional(readOnly = true)
    public MemberDistanceTotal memberTotal(UUID memberId, UUID requesterId) {
        if (!memberId.equals(requesterId) && !repository.hiddenOf(Set.of(memberId)).isEmpty()) {
            return new MemberDistanceTotal(memberId, null, null);
        }
        MemberTotal total = repository.totalOf(memberId, today().cutoff());
        return new MemberDistanceTotal(memberId, (int) Math.round(total.meters()), total.runs());
    }

    /** 내 활동 지역 탭의 내 순위. 지난주 순위는 이번 주 순위가 있을 때만 센다 */
    private MyDistanceRanking regionMe(Day day, Region region, List<MemberDistance> rows, List<Ranked> ranking,
                                       UUID requesterId) {
        Optional<MemberDistance> found = mine(rows, requesterId);
        if (found.isEmpty()) {
            return NO_RECORD;
        }
        MemberDistance mine = found.get();
        if (!mine.visible()) {
            return new MyDistanceRanking(MyDistanceRanking.Status.PRIVATE, null, mine.meters(), null, mine.periodRuns(),
                    null, null);
        }
        return new MyDistanceRanking(MyDistanceRanking.Status.RANKED, rankOf(ranking, requesterId), mine.meters(), null,
                mine.periodRuns(), null, rankOf(rank(regionLastWeek(day, region)), requesterId));
    }

    /** 이번 주 지역 랭킹. 이번 주 월요일에 그 지역에 있던 회원끼리다 */
    private List<MemberDistance> regionWeek(Day day, Region region) {
        return repository.distances(day.weekStart(), day.cutoff(), day.weekStart(), region.code(), day.weekStart());
    }

    /** 지난주 마지막 지역 랭킹. 지난주 월요일에 그 지역에 있던 회원끼리 지난주 기록 전체로 매긴다 */
    private List<MemberDistance> regionLastWeek(Day day, Region region) {
        return repository.distances(day.lastWeekStart(), day.weekStart(), day.weekStart(), region.code(), day.lastWeekStart());
    }

    /** 내 순위 카드의 `나 (닉네임)`·사진. 못 찾으면 {@code null} */
    private MemberProfile myProfile(UUID requesterId) {
        return MemberProfiles.find(memberApi, Set.of(requesterId)).get(requesterId);
    }

    /** 내 활동 지역을 아직 받지 못했으면(가입 직후 잠깐) 없는 지역과 같다 */
    private Region region(String code) {
        return Optional.ofNullable(code).flatMap(regions::findSigungu)
                .orElseThrow(() -> new AppException(RankingErrorCode.REGION_NOT_FOUND));
    }

    /** 내 정보 공개 회원만 거리 순으로. 같은 거리는 같은 순위이고 다음 순위는 그 인원만큼 건너뛴다 */
    private static List<Ranked> rank(List<MemberDistance> rows) {
        List<MemberDistance> runners = rows.stream()
                .filter(MemberDistance::visible)
                .sorted(Comparator.comparingInt(MemberDistance::meters).reversed().thenComparing(MemberDistance::memberId))
                .toList();
        List<Ranked> ranking = new ArrayList<>();
        for (int i = 0; i < runners.size(); i++) {
            boolean tie = i > 0 && runners.get(i).meters() == runners.get(i - 1).meters();
            ranking.add(new Ranked(tie ? ranking.get(i - 1).rank() : i + 1, runners.get(i)));
        }
        return ranking;
    }

    /** 순위에 없으면 {@code null} */
    private static Integer rankOf(List<Ranked> ranking, UUID memberId) {
        return ranking.stream().filter(ranked -> ranked.row().memberId().equals(memberId)).findFirst()
                .map(Ranked::rank).orElse(null);
    }

    private static Optional<MemberDistance> mine(List<MemberDistance> rows, UUID requesterId) {
        return rows.stream().filter(row -> row.memberId().equals(requesterId)).findFirst();
    }

    private List<DistanceRankingEntry> top(List<Ranked> ranking, int size, UUID requesterId, Day day) {
        return entries(ranking.subList(0, Math.min(size, ranking.size())), requesterId, day);
    }

    /** 상위 줄 다음부터 목록 API로 이어 받는 커서. 더 없으면 {@code null} */
    private static String nextCursor(List<Ranked> ranking, int size) {
        return ranking.size() > size ? String.valueOf(size) : null;
    }

    private CursorSlice<DistanceRankingEntry> page(List<Ranked> ranking, Cursorable page, UUID requesterId, Day day) {
        CursorSlice<Ranked> slice = CursorSlice.ofOffset(ranking, page);
        return new CursorSlice<>(entries(slice.content(), requesterId, day), slice.nextCursor());
    }

    private List<DistanceRankingEntry> entries(List<Ranked> ranked, UUID requesterId, Day day) {
        Map<UUID, MemberProfile> profiles = MemberProfiles.find(memberApi,
                ranked.stream().map(r -> r.row().memberId()).collect(Collectors.toSet()));
        return ranked.stream().map(r -> {
            MemberDistance row = r.row();
            MemberProfile profile = profiles.get(row.memberId());
            return new DistanceRankingEntry(r.rank(), row.memberId(), profile == null ? null : profile.nickname(),
                    profile == null ? null : profile.profileImageUrl(), row.meters(), row.periodRuns(),
                    weeklyAverage(row, day), row.memberId().equals(requesterId));
        }).toList();
    }

    /** 누적 거리 ÷ 첫 기록이 등록된 주부터 이번 주까지의 주 수, 반올림 */
    private static int weeklyAverage(MemberDistance row, Day day) {
        long weeks = ChronoUnit.WEEKS.between(monday(LocalDate.ofInstant(row.firstRegisteredAt(), TimeConfig.SEOUL)),
                day.monday()) + 1;
        return (int) Math.round(row.totalMeters() / weeks);
    }

    private Day today() {
        return new Day(LocalDate.now(clock.withZone(TimeConfig.SEOUL)));
    }

    private static LocalDate monday(LocalDate date) {
        return date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
    }

    private record Ranked(int rank, MemberDistance row) {
    }

    /** 오늘(Asia/Seoul) 기준 시각들. 오늘 00:00 전에 등록된 기록으로 계산한다 */
    private record Day(LocalDate date) {

        Instant cutoff() {
            return start(date);
        }

        LocalDate monday() {
            return DistanceRankingService.monday(date);
        }

        Instant weekStart() {
            return start(monday());
        }

        Instant lastWeekStart() {
            return start(monday().minusWeeks(1));
        }

        Instant from(RankingPeriod period) {
            return switch (period) {
                case ALL -> Instant.EPOCH;
                case MONTH -> start(date.withDayOfMonth(1));
                case WEEK -> weekStart();
            };
        }

        private static Instant start(LocalDate date) {
            return date.atStartOfDay(TimeConfig.SEOUL).toInstant();
        }
    }
}
