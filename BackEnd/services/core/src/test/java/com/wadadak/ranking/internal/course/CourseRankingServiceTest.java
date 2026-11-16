package com.wadadak.ranking.internal.course;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import com.wadadak.ranking.GhostCandidate;
import com.wadadak.ranking.RankingApi;
import com.wadadak.ranking.RankingPeriod;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.convention.TestBean;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.sql.Timestamp;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.willThrow;

/**
 * 실제 구현(app.stub.ranking=false). 지금은 2026-10-14(수) 12:00 Asia/Seoul로 고정한다.
 * 이번 주는 10-12(월) 00:00, 이번 달은 10-01 00:00부터다.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
@TestPropertySource(properties = "app.stub.ranking=false")
class CourseRankingServiceTest {

    private static final Instant THIS_WEEK = Instant.parse("2026-10-13T01:00:00Z");
    private static final Instant THIS_MONTH = Instant.parse("2026-10-02T01:00:00Z");
    private static final Instant LAST_MONTH = Instant.parse("2026-09-20T01:00:00Z");

    @Autowired
    RankingApi rankingApi;

    @Autowired
    CourseRankingReader reader;

    @Autowired
    JdbcTemplate jdbc;

    @MockitoBean
    MemberApi memberApi;

    @TestBean
    Clock clock;

    static Clock clock() {
        return Clock.fixed(Instant.parse("2026-10-14T03:00:00Z"), ZoneId.of("Asia/Seoul"));
    }

    private UUID course;
    private UUID a;
    private UUID b;
    private UUID c;
    private UUID me;

    /** {@code @ApplicationModuleTest}는 테스트 인스턴스를 클래스당 하나만 만들어서 ID를 테스트마다 새로 만든다. */
    @BeforeEach
    void records() {
        course = UUID.randomUUID();
        a = UUID.randomUUID();
        b = UUID.randomUUID();
        c = UUID.randomUUID();
        me = UUID.randomUUID();
        given(memberApi.getProfiles(any())).willAnswer(call -> call.<Set<UUID>>getArgument(0).stream()
                .map(id -> new MemberProfile(id, "닉-" + id.toString().substring(0, 4), null, false))
                .toList());
        insert(a, 300, THIS_WEEK);
        insert(a, 320, LAST_MONTH);      // a의 대표 기록은 300
        insert(b, 300, THIS_MONTH);      // a와 같은 시간이라 공동 1위. 먼저 등록돼 앞에 온다
        insert(c, 330, LAST_MONTH);
        insert(me, 340, THIS_WEEK);
        UUID deleted = insert(UUID.randomUUID(), 280, THIS_WEEK);
        jdbc.update("UPDATE ranking.course_ranking_entries SET deleted = TRUE WHERE run_record_id = ?", deleted);
        UUID hidden = UUID.randomUUID();
        insert(hidden, 270, THIS_WEEK);
        jdbc.update("INSERT INTO ranking.member_visibility_copies VALUES (?, FALSE, 1, now(), now())", hidden);
    }

    @Test
    void ranksRepresentativeRecordsWithTies() {
        CourseRankingSummary summary = reader.summary(course, RankingPeriod.ALL, me);

        // 삭제 기록(280)과 비공개 회원(270)은 빠진다.
        assertThat(summary.participantCount()).isEqualTo(4);
        assertThat(summary.averageCourseElapsedSeconds()).isEqualTo(318);   // (300+300+330+340)/4 = 317.5
        assertThat(summary.top()).extracting(CourseRankingEntry::rank).containsExactly(1, 1, 3, 4);
        assertThat(summary.top()).extracting(CourseRankingEntry::memberId).containsExactly(b, a, c, me);
        assertThat(summary.top().getFirst().nickname()).isEqualTo("닉-" + b.toString().substring(0, 4));
        assertThat(summary.me()).isEqualTo(new MyCourseRanking(MyCourseRanking.Status.RANKED, 4,
                "닉-" + me.toString().substring(0, 4), null, 340, 340, Instant.parse("2026-10-13T00:00:00Z"), 100));
        assertThat(summary.ghost().memberId()).isEqualTo(b);
    }

    @Test
    void publicSelectionRecheckHasNoTopTenLimitAndRejectsOtherPeriodsAndPrivateRecords(){
        UUID lateMember=UUID.randomUUID();
        for(int i=0;i<12;i++)insert(UUID.randomUUID(),350+i,THIS_WEEK);
        UUID late=insert(lateMember,600,THIS_WEEK);
        assertThat(rankingApi.getPublicGhostCandidates(course,RankingPeriod.ALL,me,10)).extracting(GhostCandidate::runRecordId).doesNotContain(late);
        assertThat(rankingApi.findPublicGhostCandidate(course,RankingPeriod.ALL,me,late)).isPresent();
        assertThat(rankingApi.findPublicGhostCandidate(course,RankingPeriod.ALL,lateMember,late)).isEmpty();
        UUID old=insert(UUID.randomUUID(),700,LAST_MONTH);
        assertThat(rankingApi.findPublicGhostCandidate(course,RankingPeriod.WEEK,me,old)).isEmpty();
        jdbc.update("INSERT INTO ranking.member_visibility_copies VALUES (?,FALSE,1,now(),now())",lateMember);
        assertThat(rankingApi.findPublicGhostCandidate(course,RankingPeriod.ALL,me,late)).isEmpty();
    }

    @Test
    void periodsCountByRegisteredAt() {
        assertThat(reader.summary(course, RankingPeriod.MONTH, me).top())
                .extracting(CourseRankingEntry::memberId).containsExactly(b, a, me);
        assertThat(reader.summary(course, RankingPeriod.WEEK, me).top())
                .extracting(CourseRankingEntry::memberId).containsExactly(a, me);
    }

    @Test
    void privateRequesterSeesOwnRecordWithoutRank() {
        jdbc.update("INSERT INTO ranking.member_visibility_copies VALUES (?, FALSE, 1, now(), now())", me);

        CourseRankingSummary summary = reader.summary(course, RankingPeriod.ALL, me);

        assertThat(summary.participantCount()).isEqualTo(3);
        assertThat(summary.me().status()).isEqualTo(MyCourseRanking.Status.PRIVATE);
        assertThat(summary.me().rank()).isNull();
        assertThat(summary.me().courseElapsedSeconds()).isEqualTo(340);
    }

    @Test
    void hiddenCourseHasNoRanking() {
        jdbc.update("INSERT INTO ranking.course_status_copies VALUES (?, 'HIDDEN', 1, now(), now())", course);

        assertThat(reader.summary(course, RankingPeriod.ALL, me).participantCount()).isZero();
        assertThat(rankingApi.getPublicGhostCandidates(course, RankingPeriod.ALL, me, 1)).isEmpty();
    }

    @Test
    void ghostCandidatesSkipRequester() {
        assertThat(rankingApi.getPublicGhostCandidates(course, RankingPeriod.ALL, a, RankingApi.MAX_LIMIT))
                .extracting(GhostCandidate::memberId, GhostCandidate::rank)
                .containsExactly(tuple(b, 1), tuple(c, 3), tuple(me, 4));
    }

    @Test
    void pagesEntries() {
        CursorSlice<CourseRankingEntry> first = reader.entries(course, RankingPeriod.ALL, me, new Cursorable(null, 3));
        CursorSlice<CourseRankingEntry> last = reader.entries(course, RankingPeriod.ALL, me, new Cursorable(first.nextCursor(), 3));

        assertThat(first.content()).extracting(CourseRankingEntry::rank).containsExactly(1, 1, 3);
        assertThat(last.content()).extracting(CourseRankingEntry::mine).containsExactly(true);
        assertThat(last.nextCursor()).isNull();
    }

    @Test
    void showsRankingEvenIfProfilesFail() {
        willThrow(new IllegalStateException("member 응답 없음")).given(memberApi).getProfiles(any());

        CourseRankingSummary summary = reader.summary(course, RankingPeriod.ALL, me);

        assertThat(summary.participantCount()).isEqualTo(4);
        assertThat(summary.top()).extracting(CourseRankingEntry::nickname).containsOnlyNulls();
    }

    @Test
    void publicPagesUseRepresentativesVisibilityAndStableRankingOrder() {
        var page = reader.ghostCandidates(course, RankingPeriod.ALL, me, PublicGhostSort.FASTEST, new Cursorable(null, 2));
        assertThat(page.content()).extracting(PublicGhostCandidate::memberId).containsExactly(b, a);
        assertThat(page.content()).allSatisfy(row -> {
            assertThat(row.nickname()).startsWith("닉-");
            assertThat(rankingApi.findPublicGhostCandidate(course, RankingPeriod.ALL, me, row.runRecordId())).isPresent();
        });
        var last = reader.ghostCandidates(course, RankingPeriod.ALL, me, PublicGhostSort.FASTEST, new Cursorable(page.nextCursor(), 2));
        assertThat(last.content()).extracting(PublicGhostCandidate::memberId).containsExactly(c);
        assertThat(last.nextCursor()).isNull();
        assertThat(reader.ghostCandidates(course, RankingPeriod.MONTH, me, PublicGhostSort.FASTEST, new Cursorable(null, 20)).content())
                .extracting(PublicGhostCandidate::memberId).containsExactly(b, a);
        jdbc.update("INSERT INTO ranking.course_status_copies VALUES (?, 'HIDDEN', 1, now(), now())", course);
        assertThat(reader.ghostCandidates(course, RankingPeriod.ALL, me, PublicGhostSort.FASTEST, new Cursorable(null, 20)).content()).isEmpty();
    }

    @Test
    void similarityUsesPrivateOwnBestWithoutExposingItAndFallsBackWithoutRecord() {
        jdbc.update("INSERT INTO ranking.member_visibility_copies VALUES (?, FALSE, 1, now(), now())", me);
        assertThat(reader.ghostCandidates(course, RankingPeriod.ALL, me, PublicGhostSort.SIMILAR, new Cursorable(null, 20)).content())
                .extracting(PublicGhostCandidate::memberId).containsExactly(c, b, a);
        assertThat(reader.ghostCandidates(course, RankingPeriod.ALL, UUID.randomUUID(), PublicGhostSort.SIMILAR, new Cursorable(null, 20)).content())
                .extracting(PublicGhostCandidate::memberId).containsExactly(b, a, c);
        willThrow(new IllegalStateException("profile unavailable")).given(memberApi).getProfiles(any());
        assertThat(reader.ghostCandidates(course, RankingPeriod.ALL, me, PublicGhostSort.FASTEST, new Cursorable(null, 20)).content())
                .extracting(PublicGhostCandidate::nickname).containsOnlyNulls();
    }

    @Test
    void runnerRecordIsRankedRepresentativeWithMyBest() {
        RunnerCourseRecord record = reader.runnerRecord(course, a, RankingPeriod.ALL, me);

        assertThat(record.runRecordId()).isNotNull();
        assertThat(record.rank()).isEqualTo(1);                      // b와 공동 1위
        assertThat(record.courseElapsedSeconds()).isEqualTo(300);    // 320보다 빠른 300이 대표 기록
        assertThat(record.paceSecondsPerKm()).isEqualTo(300);
        assertThat(record.myCourseElapsedSeconds()).isEqualTo(340);
        assertThat(reader.runnerRecord(course, a, RankingPeriod.ALL, UUID.randomUUID()).myCourseElapsedSeconds()).isNull();
        // c는 이번 주 기록이 없다
        assertThat(reader.runnerRecord(course, c, RankingPeriod.WEEK, me)).isNull();
    }

    @Test
    void runnerRecordIsNullForPrivateRunnerOrHiddenCourse() {
        jdbc.update("INSERT INTO ranking.member_visibility_copies VALUES (?, FALSE, 1, now(), now())", a);
        assertThat(reader.runnerRecord(course, a, RankingPeriod.ALL, me)).isNull();

        jdbc.update("INSERT INTO ranking.course_status_copies VALUES (?, 'HIDDEN', 1, now(), now())", course);
        assertThat(reader.runnerRecord(course, b, RankingPeriod.ALL, me)).isNull();
    }

    /** 기록 등록 1시간 전에 완주했다고 둔다. 코스 거리가 1000m라 페이스와 시간이 같다. */
    private UUID insert(UUID memberId, int elapsedSeconds, Instant registeredAt) {
        UUID runRecordId = UUID.randomUUID();
        jdbc.update("""
                        INSERT INTO ranking.course_ranking_entries (run_record_id, course_id, member_id, course_elapsed_seconds,
                            course_distance_meters, completed_at, registered_at, created_at, updated_at)
                        VALUES (?, ?, ?, ?, 1000, ?, ?, now(), now())""",
                runRecordId, course, memberId, elapsedSeconds, Timestamp.from(registeredAt.minus(Duration.ofHours(1))),
                Timestamp.from(registeredAt));
        return runRecordId;
    }
}
