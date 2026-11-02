package com.wadadak.course.internal.bookmark;

import com.jayway.jsonpath.JsonPath;
import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.config.TimeConfig;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.course.CourseStatusReason;
import com.wadadak.event.member.MemberWithdrawnEvent;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.transaction.support.TransactionTemplate;

import java.io.UnsupportedEncodingException;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 저장한 코스(B1-09 · G5 · C8, 정책 문서 4.1 `저장한 코스 API`). 회원은 매번 새 ID라 다른 테스트의 저장과 섞이지 않는다. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class BookmarkControllerTest {

    private static final String BASE = "/api/v1/courses/bookmarks";

    // course만 띄워서 member 모듈이 없다. 등록자 닉네임을 붙이려고 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    TransactionTemplate transactionTemplate;

    @Autowired
    ApplicationEventPublisher publisher;

    @Test
    void savesPublicCoursesOnceAndKeepsTheFirstSaveTime() {
        UUID me = UUID.randomUUID();
        UUID course = course(UUID.randomUUID(), "ACTIVE", days(10));
        UUID mine = course(me, "ACTIVE", days(10));

        assertThat(put(me, course)).hasStatusOk();
        Instant savedAt = savedAt(me, course);
        assertThat(put(me, course)).as("다시 저장해도 오류가 아니다").hasStatusOk();
        assertThat(savedAt(me, course)).as("저장 시각은 그대로").isEqualTo(savedAt);
        assertThat(put(me, mine)).as("내가 등록한 코스도 저장한다").hasStatusOk();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM course.course_bookmarks WHERE member_id = ?", Long.class, me))
                .isEqualTo(2);
    }

    @Test
    void savesOnlyPublicCoursesButKeepsAnAlreadySavedOne() {
        UUID me = UUID.randomUUID();
        UUID hidden = course(UUID.randomUUID(), "HIDDEN", days(10));
        UUID deleted = course(UUID.randomUUID(), "DELETED", days(10));
        UUID expired = course(UUID.randomUUID(), "ACTIVE", days(-2));
        UUID savedThenHidden = course(UUID.randomUUID(), "HIDDEN", days(10));
        bookmark(me, savedThenHidden, "2026-10-30T09:00:00Z");

        for (UUID id : List.of(hidden, deleted, expired)) {
            assertThat(put(me, id)).hasStatus(HttpStatus.CONFLICT).bodyJson().extractingPath("$.code").isEqualTo("COURSE-002");
        }
        assertThat(put(me, UUID.randomUUID())).hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("COURSE-001");
        assertThat(put(me, savedThenHidden)).as("이미 저장한 코스는 비공개가 돼도 같은 결과").hasStatusOk();
    }

    @Test
    void removesSeveralAtOnceAndIgnoresUnsavedCourses() {
        UUID me = UUID.randomUUID();
        UUID a = course(UUID.randomUUID(), "ACTIVE", days(10));
        UUID b = course(UUID.randomUUID(), "HIDDEN", days(10));
        UUID kept = course(UUID.randomUUID(), "ACTIVE", days(10));
        UUID other = UUID.randomUUID();
        for (UUID id : List.of(a, b, kept)) {
            bookmark(me, id, "2026-10-30T09:00:00Z");
        }
        bookmark(other, a, "2026-10-30T09:00:00Z");

        MvcTestResult result = mvc.delete().uri(BASE + "?courseIds={a}&courseIds={b}&courseIds={unknown}", a, b, UUID.randomUUID())
                .with(member(me)).exchange();

        assertThat(result).hasStatusOk();
        assertThat(status(me, a, b, kept)).containsExactly(kept.toString());
        assertThat(status(other, a)).as("다른 회원의 저장은 그대로").containsExactly(a.toString());
    }

    @Test
    void rejectsEmptyOrTooManyIds() {
        UUID me = UUID.randomUUID();
        String many = IntStream.range(0, BookmarkIdsRequest.MAX + 1).mapToObj(i -> "courseIds=" + UUID.randomUUID())
                .collect(Collectors.joining("&"));

        for (MvcTestResult result : List.of(mvc.delete().uri(BASE).with(member(me)).exchange(),
                mvc.get().uri(BASE + "/status?" + many).with(member(me)).exchange(),
                mvc.get().uri(BASE + "/status?courseIds=abc").with(member(me)).exchange())) {
            assertThat(result).hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
        }
    }

    @Test
    void listsRecentFirstWithHiddenCoursesLastAndCreatorNicknames() {
        UUID me = UUID.randomUUID();
        UUID creator = UUID.randomUUID();
        UUID older = course(creator, "ACTIVE", days(18));
        UUID hidden = course(creator, "HIDDEN", days(10));
        UUID newer = course(creator, "ACTIVE", days(1));
        UUID deleted = course(creator, "DELETED", days(10));
        bookmark(me, older, "2026-10-20T09:00:00Z");
        bookmark(me, hidden, "2026-10-31T09:00:00Z");
        bookmark(me, newer, "2026-10-30T09:00:00Z");
        bookmark(me, deleted, "2026-11-01T09:00:00Z");
        bookmark(UUID.randomUUID(), older, "2026-11-01T09:00:00Z");
        stats(newer, 13, 3);
        given(memberApi.getProfiles(any())).willReturn(List.of(new MemberProfile(creator, "러너_하늘", null, false)));

        MvcTestResult result = get(me, BASE);

        assertThat(result).hasStatusOk();
        assertThat(result).bodyJson().extractingPath("$.data.content[*].courseId").asArray()
                .as("공개 중인 코스를 최근 저장순으로, 삭제 예정은 뒤에, 삭제가 끝난 코스는 없다")
                .containsExactly(newer.toString(), older.toString(), hidden.toString());
        assertThat(result).bodyJson().extractingPath("$.data.content[0].averageRating").isEqualTo(4.3);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].creatorNickname").isEqualTo("러너_하늘");
        assertThat(result).bodyJson().extractingPath("$.data.content[0].difficulty").isEqualTo("EASY");
        assertThat(result).bodyJson().extractingPath("$.data.content[0].distanceMeters").isEqualTo(1112);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].route").asArray().hasSize(2);
        assertThat(result).bodyJson().extractingPath("$.data.content[0].deleteAt").isNull();
        assertThat(result).bodyJson().extractingPath("$.data.content[1].averageRating").isNull();
        assertThat(result).bodyJson().extractingPath("$.data.content[2].status").isEqualTo("HIDDEN");
        assertThat(result).bodyJson().extractingPath("$.data.content[2].deleteAt").isNotNull();
        assertThat(result).bodyJson().extractingPath("$.data.nextCursor").isNull();
    }

    @Test
    void sortsByRatingExpiryAndDistanceKeepingHiddenCoursesLast() {
        UUID me = UUID.randomUUID();
        UUID far = course(UUID.randomUUID(), "ACTIVE", days(25), 127.40, 37.40);
        UUID near = course(UUID.randomUUID(), "ACTIVE", days(3), 127.30, 37.30);
        UUID middle = course(UUID.randomUUID(), "ACTIVE", days(12), 127.35, 37.35);
        UUID hidden = course(UUID.randomUUID(), "HIDDEN", days(1), 127.30, 37.30);
        bookmark(me, far, "2026-10-28T09:00:00Z");
        bookmark(me, near, "2026-10-29T09:00:00Z");
        bookmark(me, middle, "2026-10-30T09:00:00Z");
        bookmark(me, hidden, "2026-10-31T09:00:00Z");
        stats(far, 9, 2);     // 4.5, 리뷰 2
        stats(middle, 18, 4); // 4.5, 리뷰 4
        stats(hidden, 5, 1);  // 5.0이지만 삭제 예정

        assertThat(ids(get(me, BASE + "?sort=RATING"))).as("평점 → 리뷰 수, 리뷰 없으면 뒤")
                .containsExactly(middle.toString(), far.toString(), near.toString(), hidden.toString());
        assertThat(ids(get(me, BASE + "?sort=EXPIRING")))
                .containsExactly(near.toString(), middle.toString(), far.toString(), hidden.toString());
        assertThat(ids(get(me, BASE + "?sort=NEAREST&lat=37.30&lng=127.30")))
                .containsExactly(near.toString(), middle.toString(), far.toString(), hidden.toString());
        assertThat(get(me, BASE + "?sort=NEAREST")).as("가까운순은 위치가 필요하다")
                .hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    @Test
    void pagesWithCursorAndKeepsTheListWhenProfilesFail() {
        UUID me = UUID.randomUUID();
        UUID first = course(UUID.randomUUID(), "ACTIVE", days(10));
        UUID second = course(UUID.randomUUID(), "ACTIVE", days(10));
        UUID third = course(UUID.randomUUID(), "ACTIVE", days(10));
        bookmark(me, first, "2026-10-30T09:00:00Z");
        bookmark(me, second, "2026-10-29T09:00:00Z");
        bookmark(me, third, "2026-10-28T09:00:00Z");
        given(memberApi.getProfiles(any())).willThrow(new IllegalStateException("member down"));

        MvcTestResult page1 = get(me, BASE + "?size=2");
        MvcTestResult page2 = get(me, BASE + "?size=2&cursor=2");

        assertThat(ids(page1)).containsExactly(first.toString(), second.toString());
        assertThat(page1).bodyJson().extractingPath("$.data.nextCursor").isEqualTo("2");
        assertThat(page1).bodyJson().extractingPath("$.data.content[0].creatorNickname").isNull();
        assertThat(ids(page2)).containsExactly(third.toString());
        assertThat(page2).bodyJson().extractingPath("$.data.nextCursor").isNull();
    }

    @Test
    void summaryCountsOnlyPublicCourses() {
        UUID me = UUID.randomUUID();
        bookmark(me, course(UUID.randomUUID(), "ACTIVE", days(7)), "2026-10-30T09:00:00Z");
        bookmark(me, course(UUID.randomUUID(), "ACTIVE", days(0)), "2026-10-30T09:00:00Z");
        bookmark(me, course(UUID.randomUUID(), "ACTIVE", days(8)), "2026-10-30T09:00:00Z");
        bookmark(me, course(UUID.randomUUID(), "HIDDEN", days(1)), "2026-10-30T09:00:00Z");
        bookmark(me, course(UUID.randomUUID(), "DELETED", days(1)), "2026-10-30T09:00:00Z");

        MvcTestResult result = get(me, BASE + "/summary");

        assertThat(result).bodyJson().extractingPath("$.data.courseCount").isEqualTo(3);
        assertThat(result).bodyJson().extractingPath("$.data.expiringSoonCount").as("D-7 · D-0까지, D-8은 아니다").isEqualTo(2);
        assertThat(get(UUID.randomUUID(), BASE + "/summary")).bodyJson().extractingPath("$.data.courseCount").isEqualTo(0);
    }

    @Test
    void clearsBookmarksWhenTheCourseIsDeletedOrTheMemberWithdraws() {
        UUID me = UUID.randomUUID();
        UUID other = UUID.randomUUID();
        UUID deleted = course(UUID.randomUUID(), "DELETED", days(10));
        UUID hidden = course(UUID.randomUUID(), "HIDDEN", days(10));
        UUID kept = course(UUID.randomUUID(), "ACTIVE", days(10));
        bookmark(me, deleted, "2026-10-30T09:00:00Z");
        bookmark(other, deleted, "2026-10-30T09:00:00Z");
        bookmark(me, hidden, "2026-10-30T09:00:00Z");
        bookmark(other, kept, "2026-10-30T09:00:00Z");

        receive(new CourseStatusChangedEvent(UUID.randomUUID(), Instant.now(), hidden, CourseStatus.HIDDEN,
                CourseStatusReason.EXPIRED, 1));
        receive(new CourseStatusChangedEvent(UUID.randomUUID(), Instant.now(), deleted, CourseStatus.DELETED,
                CourseStatusReason.EXPIRED, 2));
        assertThat(status(me, deleted, hidden)).as("삭제 예정은 남고 삭제가 끝난 코스는 지운다").containsExactly(hidden.toString());
        assertThat(status(other, deleted)).isEmpty();

        receive(new MemberWithdrawnEvent(UUID.randomUUID(), Instant.now(), other, Instant.now()));
        assertThat(status(other, kept)).isEmpty();
        assertThat(status(me, hidden)).as("다른 회원의 저장은 그대로").containsExactly(hidden.toString());
    }

    private MvcTestResult put(UUID memberId, UUID courseId) {
        return mvc.put().uri(BASE + "/" + courseId).with(member(memberId)).exchange();
    }

    private MvcTestResult get(UUID memberId, String uri) {
        return mvc.get().uri(uri).with(member(memberId)).exchange();
    }

    private List<Object> status(UUID memberId, UUID... courseIds) {
        String query = Arrays.stream(courseIds).map(id -> "courseIds=" + id).collect(Collectors.joining("&"));
        MvcTestResult result = get(memberId, BASE + "/status?" + query);
        assertThat(result).hasStatusOk();
        return ids(result, "$.data");
    }

    private static List<Object> ids(MvcTestResult result) {
        return ids(result, "$.data.content[*].courseId");
    }

    @SuppressWarnings("unchecked")
    private static List<Object> ids(MvcTestResult result, String path) {
        try {
            return (List<Object>) JsonPath.read(result.getResponse().getContentAsString(StandardCharsets.UTF_8), path);
        } catch (UnsupportedEncodingException e) {
            throw new IllegalStateException(e);
        }
    }

    private static RequestPostProcessor member(UUID memberId) {
        return jwt().jwt(j -> j.subject(memberId.toString()));
    }

    private Instant savedAt(UUID memberId, UUID courseId) {
        return jdbc.queryForObject("SELECT created_at FROM course.course_bookmarks WHERE member_id = ? AND course_id = ?",
                Timestamp.class, memberId, courseId).toInstant();
    }

    private void receive(Object event) {
        transactionTemplate.executeWithoutResult(status -> publisher.publishEvent(event));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(jdbc.queryForObject("SELECT count(*) FROM common.event_publication", Long.class)).isZero());
    }

    /** 만료 시각. 오늘에서 [days]일 뒤 23:59:59(Asia/Seoul) 근처다 */
    private static Instant days(int days) {
        return LocalDate.now(TimeConfig.SEOUL).plusDays(days).atTime(23, 59, 59)
                .atZone(TimeConfig.SEOUL).toInstant();
    }

    private UUID course(UUID creatorId, String status, Instant expiresAt) {
        return course(creatorId, status, expiresAt, 127.30, 37.30);
    }

    /** 비공개 · 삭제된 코스는 등록자가 지웠다. 출발점은 ([lng], [lat]) */
    private UUID course(UUID creatorId, String status, Instant expiresAt, double lng, double lat) {
        UUID id = UUID.randomUUID();
        boolean active = status.equals("ACTIVE");
        Timestamp now = Timestamp.from(Instant.now());
        jdbc.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    status_reason, hidden_at, expires_at, version, created_at, updated_at)
                        VALUES (?, ?, 'CUSTOM', ?, ?, 'EASY', '{FLAT}'::varchar[],
                                ST_GeomFromText('LINESTRING(127.30 37.30, 127.30 37.31)', 4326), 1112,
                                ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, '1171010100', '1171000000', '1100000000',
                                ?, ?, ?, ?, 0, ?, ?)""",
                id, creatorId, "저장 코스 " + id, "저장코스" + id, lng, lat, status, active ? null : "USER_DELETED",
                active ? null : now, Timestamp.from(expiresAt), now, now);
        return id;
    }

    private void bookmark(UUID memberId, UUID courseId, String savedAt) {
        Timestamp at = Timestamp.from(Instant.parse(savedAt));
        jdbc.update("INSERT INTO course.course_bookmarks (member_id, course_id, created_at, updated_at) VALUES (?, ?, ?, ?)",
                memberId, courseId, at, at);
    }

    private void stats(UUID courseId, int ratingSum, int reviews) {
        jdbc.update("""
                        INSERT INTO course.course_stats (course_id, completion_count, rating_sum, review_count, created_at, updated_at)
                        VALUES (?, 0, ?, ?, now(), now())""", courseId, ratingSum, reviews);
    }
}
