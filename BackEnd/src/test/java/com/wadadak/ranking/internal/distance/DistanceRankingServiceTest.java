package com.wadadak.ranking.internal.distance;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.region.RegionDirectory;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import com.wadadak.ranking.RankingErrorCode;
import com.wadadak.ranking.RankingPeriod;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.convention.TestBean;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;

/**
 * 실제 구현(app.stub.ranking=false). 지금은 2026-10-14(수) 12:00 Asia/Seoul로 고정한다.
 * 오늘 00:00 전에 등록된 기록으로 계산한다. 이번 주는 10-12(월), 지난주는 10-05(월), 이번 달은 10-01부터다.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class DistanceRankingServiceTest {

    private static final Instant TODAY = Instant.parse("2026-10-14T01:00:00Z");          // 10-14(수) 10:00, 자정 뒤
    private static final Instant THIS_WEEK = Instant.parse("2026-10-13T01:00:00Z");      // 10-13(화) 10:00
    private static final Instant MONDAY_EARLY = Instant.parse("2026-10-11T16:00:00Z");   // 10-12(월) 01:00
    private static final Instant LAST_WEEK = Instant.parse("2026-10-08T01:00:00Z");      // 10-08(목) 10:00
    private static final Instant LAST_MONTH = Instant.parse("2026-09-20T01:00:00Z");     // 09-20(일) 10:00
    private static final String SEONGBUK = "1129000000";
    private static final String JONGNO = "1111000000";

    // 같은 거리면 회원 ID순이라 순서를 정해 둔다
    private static final UUID A = id(1);
    private static final UUID B = id(2);
    private static final UUID C = id(3);
    private static final UUID F = id(4);
    private static final UUID G = id(5);
    private static final UUID H = id(6);
    private static final UUID I = id(7);
    private static final UUID J = id(8);
    private static final UUID K = id(9);
    private static final UUID ME = id(100);

    @Autowired
    DistanceRankingReader reader;

    @Autowired
    RegionDirectory regions;

    @Autowired
    JdbcTemplate jdbc;

    @MockitoBean
    MemberApi memberApi;

    @TestBean
    Clock clock;

    static Clock clock() {
        return Clock.fixed(Instant.parse("2026-10-14T03:00:00Z"), ZoneId.of("Asia/Seoul"));
    }

    /** 누적 거리 랭킹은 회원 전체가 대상이라 테스트마다 ranking 기록을 새로 깐다. */
    @BeforeEach
    void records() {
        jdbc.update("DELETE FROM ranking.distance_run_records");
        jdbc.update("DELETE FROM ranking.member_region_history");
        jdbc.update("DELETE FROM ranking.member_visibility_copies");
        given(memberApi.getProfiles(any())).willAnswer(call -> call.<Set<UUID>>getArgument(0).stream()
                .map(id -> new MemberProfile(id, "러너" + id.getLeastSignificantBits(), null, false))
                .toList());

        run(A, 10_000, THIS_WEEK);
        run(A, 5_000, LAST_MONTH);
        run(B, 15_000, LAST_WEEK);           // 누적은 A와 같은 15km라 공동 1위
        run(C, 12_000, LAST_MONTH);
        run(ME, 8_000.4, THIS_WEEK);
        run(ME, 1_999.7, LAST_WEEK);         // 누적 10,000.1m는 10,000m로 센다
        run(F, 1_000, LAST_MONTH);
        run(G, 3_000, MONDAY_EARLY);
        run(H, 30_000, THIS_WEEK);           // 비공개
        jdbc.update("INSERT INTO ranking.member_visibility_copies VALUES (?, FALSE, 1, now(), now())", H);
        run(I, 5_000, LAST_WEEK);
        run(J, 6_000, THIS_WEEK);
        run(J, 7_000, LAST_WEEK);
        run(K, 4_000, THIS_WEEK);
        jdbc.update("""
                INSERT INTO ranking.distance_run_records (run_record_id, member_id, distance_meters, registered_at, deleted)
                VALUES (?, ?, 50000, ?, TRUE)""", UUID.randomUUID(), id(10), Timestamp.from(THIS_WEEK));   // 지운 기록
        run(id(11), 40_000, TODAY);         // 오늘 등록돼 내일 들어간다

        for (UUID member : new UUID[]{A, C, H, I}) {
            region(member, 0, SEONGBUK, "2026-09-14");
        }
        region(B, 0, JONGNO, "2026-09-14");
        region(K, 0, JONGNO, "2026-09-14");
        region(ME, 0, SEONGBUK, "2026-09-14");
        region(ME, 1, JONGNO, "2026-10-19");    // 이번 주에 바꿔서 다음 주부터 종로
        region(G, 0, SEONGBUK, "2026-10-12");   // 이번 주 가입
        region(J, 0, JONGNO, "2026-09-07");
        region(J, 1, SEONGBUK, "2026-10-12");   // 지난주에 바꿔서 이번 주부터 성북
    }

    @Test
    void ranksAllTimeDistanceUntilMidnightWithTies() {
        DistanceRankingSummary summary = reader.summary(RankingPeriod.ALL, ME);

        // 비공개(H)·지운 기록(id 10)·오늘 기록(id 11)은 빠진다
        assertThat(summary.participantCount()).isEqualTo(9);
        assertThat(summary.calculatedAt()).isEqualTo(Instant.parse("2026-10-13T15:00:00Z"));
        assertThat(summary.top()).extracting(DistanceRankingEntry::memberId).containsExactly(A, B, J);
        assertThat(summary.top()).extracting(DistanceRankingEntry::rank).containsExactly(1, 1, 3);
        assertThat(summary.top()).extracting(DistanceRankingEntry::distanceMeters).containsExactly(15_000, 15_000, 13_000);
        assertThat(summary.top().getFirst().nickname()).isEqualTo("러너1");
        assertThat(summary.nextCursor()).isEqualTo("3");
        // 5위 / 9명 = 55.6% → 56
        assertThat(summary.me()).isEqualTo(new MyDistanceRanking(MyDistanceRanking.Status.RANKED, 5, 10_000, 8_000, 2, 56, null));
    }

    @Test
    void continuesAfterPodiumWithWeeklyAverage() {
        CursorSlice<DistanceRankingEntry> page = reader.entries(RankingPeriod.ALL, ME, new Cursorable("3", 3));

        assertThat(page.content()).extracting(DistanceRankingEntry::memberId).containsExactly(C, ME, I);
        assertThat(page.content()).extracting(DistanceRankingEntry::rank).containsExactly(4, 5, 6);
        assertThat(page.content()).extracting(DistanceRankingEntry::mine).containsExactly(false, true, false);
        // 주 평균 = 누적 ÷ 첫 기록 주부터 이번 주까지 주 수. C는 09-14 주부터 5주, 나는 10-05 주부터 2주
        assertThat(page.content()).extracting(DistanceRankingEntry::weeklyAverageMeters).containsExactly(2_400, 5_000, 2_500);
        assertThat(page.content()).extracting(DistanceRankingEntry::runCount).containsExactly(1, 2, 1);
        assertThat(page.nextCursor()).isEqualTo("6");
    }

    @Test
    void periodsCountByRegisteredAt() {
        DistanceRankingSummary month = reader.summary(RankingPeriod.MONTH, ME);
        // A와 나는 이번 달 10km로 공동 3위. ID가 앞선 A가 먼저다
        assertThat(month.participantCount()).isEqualTo(7);
        assertThat(month.top()).extracting(DistanceRankingEntry::memberId).containsExactly(B, J, A);
        assertThat(month.me()).isEqualTo(new MyDistanceRanking(MyDistanceRanking.Status.RANKED, 3, 10_000, 8_000, 2, 43, null));

        DistanceRankingSummary week = reader.summary(RankingPeriod.WEEK, ME);
        // 월요일 01:00 기록(G)은 이번 주다
        assertThat(week.participantCount()).isEqualTo(5);
        assertThat(reader.entries(RankingPeriod.WEEK, ME, new Cursorable(null, 50)).content())
                .extracting(DistanceRankingEntry::memberId).containsExactly(A, ME, J, K, G);
        assertThat(week.me()).isEqualTo(new MyDistanceRanking(MyDistanceRanking.Status.RANKED, 2, 8_000, 8_000, 1, 40, null));
    }

    @Test
    void privateRunnerSeesOwnDistanceWithoutRank() {
        DistanceRankingSummary week = reader.summary(RankingPeriod.WEEK, H);

        assertThat(week.participantCount()).isEqualTo(5);
        assertThat(week.me()).isEqualTo(new MyDistanceRanking(MyDistanceRanking.Status.PRIVATE, null, 30_000, 30_000, 1, null, null));
        assertThat(reader.regionWeekly(null, H).me())
                .isEqualTo(new MyDistanceRanking(MyDistanceRanking.Status.PRIVATE, null, 30_000, null, 1, null, null));
    }

    @Test
    void runnerWithoutRecordHasNoRank() {
        assertThat(reader.summary(RankingPeriod.ALL, UUID.randomUUID()).me())
                .isEqualTo(new MyDistanceRanking(MyDistanceRanking.Status.NO_RECORD, null, null, null, null, null, null));
        assertThat(reader.summary(RankingPeriod.MONTH, C).me().status()).isEqualTo(MyDistanceRanking.Status.NO_RECORD);
    }

    @Test
    void regionWeeklyGroupsByRegionAtMondayAndComparesLastWeek() {
        RegionWeeklyRanking ranking = reader.regionWeekly(null, ME);

        // 나는 이번 주에 종로로 바꿨지만 이번 주는 성북이다. G는 이번 주 가입, J는 지난주에 바꿔 이번 주부터 성북
        assertThat(ranking.region().code()).isEqualTo(SEONGBUK);
        assertThat(ranking.weekStart()).isEqualTo(LocalDate.parse("2026-10-12"));
        assertThat(ranking.calculatedAt()).isEqualTo(Instant.parse("2026-10-13T15:00:00Z"));
        assertThat(ranking.participantCount()).isEqualTo(4);
        assertThat(ranking.top()).extracting(DistanceRankingEntry::memberId).containsExactly(A, ME, J, G);
        assertThat(ranking.nextCursor()).isNull();
        // 지난주 성북은 I(5km)·나(2km). J의 지난주 7km는 그때 종로라 빠진다
        assertThat(ranking.me()).isEqualTo(new MyDistanceRanking(MyDistanceRanking.Status.RANKED, 2, 8_000, null, 1, null, 2));
        assertThat(reader.regionWeeklyEntries(null, ME, new Cursorable("2", 2)).content())
                .extracting(DistanceRankingEntry::rank).containsExactly(3, 4);
    }

    @Test
    void otherRegionHasNoRankForMe() {
        RegionWeeklyRanking jongno = reader.regionWeekly(regions.findSigungu(JONGNO).orElseThrow(), ME);

        assertThat(jongno.top()).extracting(DistanceRankingEntry::memberId).containsExactly(K);
        assertThat(jongno.me().status()).isEqualTo(MyDistanceRanking.Status.OTHER_REGION);
    }

    @Test
    void myRegionUnknownYetIsRegionNotFound() {
        assertThatThrownBy(() -> reader.regionWeekly(null, UUID.randomUUID()))
                .isInstanceOfSatisfying(AppException.class,
                        e -> assertThat(e.getErrorCode()).isEqualTo(RankingErrorCode.REGION_NOT_FOUND));
    }

    private void run(UUID member, double meters, Instant registeredAt) {
        jdbc.update("INSERT INTO ranking.distance_run_records (run_record_id, member_id, distance_meters, registered_at) VALUES (?, ?, ?, ?)",
                UUID.randomUUID(), member, meters, Timestamp.from(registeredAt));
    }

    /** @param effectiveFrom 그 지역 랭킹에 들어가는 첫 주의 월요일 */
    private void region(UUID member, long version, String regionCode, String effectiveFrom) {
        jdbc.update("INSERT INTO ranking.member_region_history VALUES (?, ?, ?, ?, now(), now())", member, version, regionCode,
                Timestamp.from(LocalDate.parse(effectiveFrom).atStartOfDay(TimeConfig.SEOUL).toInstant()));
    }

    private static UUID id(long n) {
        return new UUID(0, n);
    }
}
