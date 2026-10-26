package com.wadadak.course.internal.explore;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.course.internal.course.CourseName;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.assertj.MvcTestResult;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;

/** 지도 테스트(위도 33.40~33.53) · 상세 테스트(33.70~33.71)와 겹치지 않게 위도 33.60부터, 테스트마다 다른 지도 범위를 쓴다. */
@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CourseListControllerTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    private static final Instant NOW = Instant.parse("2026-10-01T00:00:00Z");

    @Autowired
    MockMvcTester mvc;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    JsonMapper jsonMapper;

    @Test
    void listsActiveCoursesInTheAreaNewestFirstPageByPage() throws Exception {
        UUID oldest = insert(33.601, 126.301, NOW, "MEDIUM", 3_210, "{SHADE,FLAT}", "GPS");
        UUID middle = insert(33.602, 126.302, NOW.plusSeconds(1));
        UUID newest = insert(33.603, 126.303, NOW.plusSeconds(2));
        // 출발점이 범위 밖(남쪽)
        insert(33.599, 126.301, NOW.plusSeconds(3));
        UUID hidden = insert(33.604, 126.304, NOW.plusSeconds(4));
        jdbcTemplate.update("UPDATE course.courses SET status = 'HIDDEN', status_reason = 'EXPIRED', hidden_at = now() WHERE id = ?",
                hidden);
        String query = "swLat=33.600&swLng=126.300&neLat=33.610&neLng=126.310&sort=LATEST&size=2";

        JsonNode first = data(list(query));
        assertThat(ids(first)).containsExactly(newest, middle);
        assertThat(first.get("nextCursor").isNull()).isFalse();

        // 쪽을 넘기는 사이 새 코스가 등록돼도 이미 받은 코스가 다시 나오지 않는다.
        insert(33.605, 126.305, NOW.plusSeconds(5));
        JsonNode second = data(list(query + "&cursor=" + first.get("nextCursor").asString()));
        assertThat(ids(second)).containsExactly(oldest);
        assertThat(second.get("nextCursor").isNull()).isTrue();

        JsonNode card = second.get("content").get(0);
        assertThat(card.get("name").asString()).isEqualTo("목록 코스 " + oldest);
        assertThat(card.get("distanceMeters").asInt()).isEqualTo(3_210);
        assertThat(card.get("difficulty").asString()).isEqualTo("MEDIUM");
        // FIL-04 순서
        List<String> tags = new ArrayList<>();
        card.get("tags").forEach(tag -> tags.add(tag.asString()));
        assertThat(tags).containsExactly("FLAT", "SHADE");
        assertThat(card.get("courseType").asString()).isEqualTo("GPS");
        assertThat(Instant.parse(card.get("expiresAt").asString())).isEqualTo(NOW.plusSeconds(30 * 24 * 3600));
        // 첫 점이 출발점
        assertThat(card.get("route").get(0).get("lat").asDouble()).isEqualTo(33.601);
        assertThat(card.get("route").get(0).get("lng").asDouble()).isEqualTo(126.301);
    }

    @Test
    void listsNearestFirstFromTheCurrentLocation() throws Exception {
        UUID far = insert(33.629, 126.309, NOW);
        UUID near = insert(33.6252, 126.305, NOW.plusSeconds(1));
        UUID middle = insert(33.627, 126.305, NOW.plusSeconds(2));
        // 같은 곳에서 출발하면 ID순
        UUID sameA = insert(33.628, 126.305, NOW.plusSeconds(3));
        UUID sameB = insert(33.628, 126.305, NOW.plusSeconds(4));
        List<UUID> same = Stream.of(sameA, sameB).sorted(Comparator.comparing(UUID::toString)).toList();
        String query = "swLat=33.620&swLng=126.300&neLat=33.630&neLng=126.310&sort=NEAREST&lat=33.625&lng=126.305&size=3";

        JsonNode first = data(list(query));
        assertThat(ids(first)).containsExactly(near, middle, same.get(0));
        JsonNode second = data(list(query + "&cursor=" + first.get("nextCursor").asString()));
        assertThat(ids(second)).containsExactly(same.get(1), far);
        assertThat(second.get("nextCursor").isNull()).isTrue();
    }

    @Test
    void listsTheSameCoursesAsTheMap() throws Exception {
        UUID hardShort = insert(33.641, 126.301, NOW, "HARD", 3_000, "{}", "CUSTOM");
        insert(33.642, 126.302, NOW, "EASY", 3_000, "{}", "CUSTOM");
        insert(33.643, 126.303, NOW, "HARD", 6_000, "{}", "CUSTOM");
        String area = "swLat=33.640&swLng=126.300&neLat=33.650&neLng=126.310&difficulties=HARD&maxDistanceMeters=5000";

        List<UUID> listed = ids(data(list(area + "&sort=LATEST")));
        assertThat(listed).containsExactly(hardShort);

        // 지도와 같은 조건이다(MAP-07).
        List<UUID> mapped = new ArrayList<>();
        data(mvc.get().uri("/api/v1/courses/map?" + area).with(jwt()).exchange())
                .get("courses").forEach(course -> mapped.add(UUID.fromString(course.get("courseId").asString())));
        assertThat(mapped).isEqualTo(listed);
    }

    /** G6에서 고른 검색어 · 지역(SEA-04 · SEA-07)은 목록 · 지도 · 지역별 코스 수에 같이 걸린다. */
    @Test
    void narrowsToTheSearchWordAndRegionPickedInG6() throws Exception {
        String word = UUID.randomUUID().toString().replace("-", "").substring(0, 8);
        UUID picked = insertNamed("한강 " + word + " 야경", 33.761, 126.301, "1156000000");
        // 검색어는 같지만 다른 지역, 같은 지역이지만 다른 이름
        insertNamed("한강 " + word, 33.762, 126.302, "1114000000");
        insertNamed("여의도 코스", 33.763, 126.303, "1156000000");
        String area = "swLat=33.760&swLng=126.300&neLat=33.770&neLng=126.310";
        String picks = "&query=" + word.toUpperCase(java.util.Locale.ROOT) + "&regionCode=1156000000";

        assertThat(ids(data(list(area + picks + "&sort=LATEST")))).containsExactly(picked);
        JsonNode map = data(mvc.get().uri("/api/v1/courses/map?" + area + picks).with(jwt()).exchange());
        assertThat(map.get("totalCount").asInt()).isEqualTo(1);
        assertThat(map.get("courses").get(0).get("courseId").asString()).isEqualTo(picked.toString());
        JsonNode regions = data(mvc.get().uri("/api/v1/courses/map/regions?" + area + picks + "&level=DISTRICT").with(jwt()).exchange());
        assertThat(regions.get("totalCount").asInt()).isEqualTo(1);
        // 검색어만, 지역만 걸 수도 있다
        assertThat(ids(data(list(area + "&query=" + word + "&sort=LATEST")))).hasSize(2);
        assertThat(ids(data(list(area + "&regionCode=1156000000&sort=LATEST")))).hasSize(2);

        assertBadRequest(list(area + "&query=a&sort=LATEST"));
        assertBadRequest(list(area + "&regionCode=1156&sort=LATEST"));
    }

    /**
     * 평점순은 카드에 보이는 평점(소수 첫째 자리 반올림)이 높은 코스부터, 같으면 리뷰 수가 많은 코스, 그다음 최신순이다.
     * 리뷰가 없는 코스는 맨 뒤다. 최소 평점도 보이는 평점으로 거르고 리뷰가 없는 코스는 뺀다.
     */
    @Test
    void listsTopRatedFirstAndFiltersByTheShownRating() throws Exception {
        UUID five = insert(33.661, 126.301, NOW);
        UUID manyReviews = insert(33.662, 126.302, NOW);
        // 정확한 평균(4.71)은 위 코스(4.70)보다 높지만 보이는 평점이 같아 리뷰 수로 정한다
        UUID fewReviews = insert(33.663, 126.303, NOW);
        UUID olderSame = insert(33.664, 126.304, NOW.minusSeconds(60));
        UUID roundedUp = insert(33.665, 126.305, NOW);
        UUID noReviews = insert(33.666, 126.306, NOW.plusSeconds(60));
        reviews(five, 5, 1);
        reviews(manyReviews, 47, 10);
        reviews(fewReviews, 33, 7);
        reviews(olderSame, 33, 7);
        reviews(roundedUp, 93, 20); // 4.65 → 4.7
        String area = "swLat=33.660&swLng=126.300&neLat=33.670&neLng=126.310";
        String query = area + "&sort=RATING&size=2";

        List<UUID> all = new ArrayList<>();
        JsonNode page = data(list(query));
        all.addAll(ids(page));
        while (!page.get("nextCursor").isNull()) {
            page = data(list(query + "&cursor=" + page.get("nextCursor").asString()));
            all.addAll(ids(page));
        }
        // 4.7 넷 중 리뷰 수 20 · 10 · 7(최신) · 7(오래됨)
        assertThat(all).containsExactly(five, roundedUp, manyReviews, fewReviews, olderSame, noReviews);

        JsonNode cards = data(list(area + "&sort=RATING&size=10")).get("content");
        assertThat(cards.get(0).get("averageRating").asDouble()).isEqualTo(5.0);
        assertThat(cards.get(0).get("reviewCount").asInt()).isEqualTo(1);
        assertThat(cards.get(1).get("averageRating").asDouble()).isEqualTo(4.7);
        assertThat(cards.get(5).get("averageRating").isNull()).isTrue();
        assertThat(cards.get(5).get("reviewCount").asInt()).isZero();

        assertThat(ids(data(list(area + "&sort=LATEST&minRating=4.7"))))
                .containsExactlyInAnyOrder(five, roundedUp, manyReviews, fewReviews, olderSame);
        assertThat(ids(data(list(area + "&sort=LATEST&minRating=4.8")))).containsExactly(five);
        // 지도 · 지역별 코스 수도 같은 조건이다(MAP-07)
        JsonNode map = data(mvc.get().uri("/api/v1/courses/map?" + area + "&minRating=4.8").with(jwt()).exchange());
        assertThat(map.get("totalCount").asInt()).isEqualTo(1);
        assertThat(map.get("courses").get(0).get("averageRating").asDouble()).isEqualTo(5.0);
        assertThat(data(mvc.get().uri("/api/v1/courses/map/regions?" + area + "&minRating=4.8&level=DISTRICT").with(jwt())
                .exchange()).get("totalCount").asInt()).isEqualTo(1);
    }

    /**
     * 인기순은 도전 수 → 조회 수 → 리뷰 수가 많은 코스부터, 모두 같으면 최신순이다(FIL-01).
     * 0 아래로 내려간 수(도전 수를 더하기 전 기록을 지운 경우)는 0으로 본다.
     */
    @Test
    void listsPopularFirstByChallengesThenViewsThenReviews() throws Exception {
        UUID mostChallenged = insert(33.681, 126.301, NOW);
        UUID moreViews = insert(33.682, 126.302, NOW);
        UUID moreReviews = insert(33.683, 126.303, NOW);
        UUID newerSame = insert(33.684, 126.304, NOW.plusSeconds(10));
        UUID olderSame = insert(33.685, 126.305, NOW.minusSeconds(10));
        UUID belowZero = insert(33.686, 126.306, NOW);
        UUID nothing = insert(33.687, 126.307, NOW.plusSeconds(60));
        stats(mostChallenged, 5, 0, 0);
        stats(moreViews, 3, 10, 0);
        stats(moreReviews, 3, 2, 4);
        stats(newerSame, 3, 2, 1);
        stats(olderSame, 3, 2, 1);
        stats(belowZero, -2, 1, 0);
        String query = "swLat=33.680&swLng=126.300&neLat=33.690&neLng=126.310&sort=POPULAR&size=2";

        assertThat(allPages(query))
                .containsExactly(mostChallenged, moreViews, moreReviews, newerSame, olderSame, belowZero, nothing);
    }

    /** 실시간순은 지금 달리는 러너가 많은 코스부터, 같으면 인기순(도전 수 → 조회 수 → 리뷰 수 → 최신순)이다. */
    @Test
    void listsLiveByRunnersThenPopularityAndShowsRunnersOnCards() throws Exception {
        UUID twoRunners = insert(33.741, 126.321, NOW);
        UUID oneRunnerPopular = insert(33.742, 126.322, NOW);
        UUID oneRunner = insert(33.743, 126.323, NOW);
        UUID noneNowPopular = insert(33.744, 126.324, NOW);
        UUID neverReported = insert(33.745, 126.325, NOW.plusSeconds(60));
        runners(twoRunners, 2);
        runners(oneRunnerPopular, 1);
        runners(oneRunner, 1);
        runners(noneNowPopular, 0);
        stats(oneRunnerPopular, 9, 0, 0);
        stats(oneRunner, 1, 0, 0);
        stats(noneNowPopular, 20, 0, 0);
        String area = "swLat=33.740&swLng=126.320&neLat=33.750&neLng=126.330";

        assertThat(allPages(area + "&sort=LIVE&size=2"))
                .containsExactly(twoRunners, oneRunnerPopular, oneRunner, noneNowPopular, neverReported);

        // 카드 · 지도 범위 안 코스에도 현재 러너 수가 있다. 받은 적이 없으면 0명
        JsonNode cards = data(list(area + "&sort=LIVE")).get("content");
        assertThat(cards.get(0).get("activeRunners").asInt()).isEqualTo(2);
        assertThat(cards.get(4).get("activeRunners").asInt()).isZero();
        JsonNode map = data(mvc.get().uri("/api/v1/courses/map?" + area).with(jwt()).exchange());
        map.get("courses").forEach(course -> {
            if (course.get("courseId").asString().equals(twoRunners.toString())) {
                assertThat(course.get("activeRunners").asInt()).isEqualTo(2);
            }
        });
    }

    /**
     * 인기순 기간(FIL-09)은 그 기간(두 날짜 포함)의 도전 수 · 조회 수 · 리뷰 수로 정렬한다.
     * 기간에 값이 없는 코스도 빠지지 않고 뒤에 오고, 지도 코스 수는 그대로다.
     */
    @Test
    void popularInAPeriodSortsByThatPeriodWithoutDroppingCourses() throws Exception {
        UUID popularBefore = insert(33.721, 126.301, NOW.plusSeconds(30));
        UUID twoInPeriod = insert(33.722, 126.302, NOW);
        UUID oneWithViews = insert(33.723, 126.303, NOW);
        UUID oneOnEndDay = insert(33.724, 126.304, NOW);
        UUID nothing = insert(33.725, 126.305, NOW.minusSeconds(30));
        stats(popularBefore, 100, 0, 0);
        daily(popularBefore, "2026-10-13", 100, 0, 0);       // 시작일 전날
        daily(twoInPeriod, "2026-10-14", 2, 0, 0);           // 시작일 당일
        daily(oneWithViews, "2026-10-15", 1, 5, 0);
        daily(oneWithViews, "2026-10-17", 50, 0, 0);         // 종료일 다음 날
        daily(oneOnEndDay, "2026-10-16", 1, 1, 0);           // 종료일 당일
        String area = "swLat=33.720&swLng=126.300&neLat=33.730&neLng=126.310";

        assertThat(allPages(area + "&sort=POPULAR&size=2&startDate=2026-10-14&endDate=2026-10-16"))
                .containsExactly(twoInPeriod, oneWithViews, oneOnEndDay, popularBefore, nothing);
        // 시작일만: 10/16부터 oneWithViews는 50, oneOnEndDay는 1
        assertThat(ids(data(list(area + "&sort=POPULAR&startDate=2026-10-16"))))
                .containsExactly(oneWithViews, oneOnEndDay, popularBefore, twoInPeriod, nothing);
        // 종료일만: 10/13까지는 popularBefore만
        assertThat(ids(data(list(area + "&sort=POPULAR&endDate=2026-10-13"))).getFirst()).isEqualTo(popularBefore);
        // 기간이 없으면 누적 통계다
        assertThat(ids(data(list(area + "&sort=POPULAR"))).getFirst()).isEqualTo(popularBefore);
        // 기간은 순서만 바꾼다. 지도 코스 수(예상 코스 수)는 그대로다
        assertThat(data(mvc.get().uri("/api/v1/courses/map?" + area).with(jwt()).exchange()).get("totalCount").asInt())
                .isEqualTo(5);
    }

    @Test
    void rejectsBadListRequests() {
        String area = "swLat=33.6&swLng=126.3&neLat=33.7&neLng=126.4";
        String latestCursor = CourseListCursor.latest(NOW, UUID.randomUUID()).encode();

        assertBadRequest(list(area));
        assertBadRequest(list(area + "&sort=NEAREST"));
        assertBadRequest(list(area + "&sort=NEAREST&lat=33.65"));
        assertBadRequest(list(area + "&sort=NEAREST&lat=91&lng=126.35"));
        assertBadRequest(list(area + "&sort=LATEST&cursor=garbage"));
        assertBadRequest(list(area + "&sort=NEAREST&lat=33.65&lng=126.35&cursor=" + latestCursor));
        assertBadRequest(list(area + "&sort=LATEST&size=51"));
        assertBadRequest(list("swLat=33.7&swLng=126.3&neLat=33.6&neLng=126.4&sort=LATEST"));
        assertBadRequest(list(area + "&sort=LATEST&minRating=5.1"));
        assertBadRequest(list(area + "&sort=RATING&cursor=" + latestCursor));
        assertBadRequest(list(area + "&sort=POPULAR&cursor=" + latestCursor));
        UUID id = UUID.randomUUID();
        String popularCursor = CourseListCursor.popular(new CourseListCursor.Counts(List.of(3L, 2L, 1L), NOW), id).encode();
        assertBadRequest(list(area + "&sort=LIVE&cursor=" + popularCursor));
        assertBadRequest(list(area + "&sort=POPULAR&cursor=" + new CourseListCursor(CourseListSort.POPULAR, "3_2_1", id).encode()));
        assertBadRequest(list(area + "&sort=POPULAR&cursor="
                + new CourseListCursor(CourseListSort.POPULAR, "3_-2_1_0", id).encode()));
        assertBadRequest(list(area + "&sort=LIVE&cursor=" + new CourseListCursor(CourseListSort.LIVE, "1_3_2_1", id).encode()));
        // 기간은 인기순에만, 시작일 ≤ 종료일
        assertBadRequest(list(area + "&sort=RATING&startDate=2026-10-01"));
        assertBadRequest(list(area + "&sort=LIVE&endDate=2026-10-01"));
        assertBadRequest(list(area + "&sort=POPULAR&startDate=2026-10-02&endDate=2026-10-01"));
        assertBadRequest(list(area + "&sort=POPULAR&startDate=2026.10.01"));
        assertThat(list(area + "&sort=POPULAR&startDate=2026-10-01&endDate=2026-10-01")).hasStatusOk();
        assertThat(list(area + "&sort=POPULAR&cursor=" + popularCursor)).hasStatusOk();
        assertThat(list(area + "&sort=LIVE&cursor="
                + CourseListCursor.live(new CourseListCursor.Counts(List.of(0L, 0L, 0L, 0L), NOW), id).encode())).hasStatusOk();
        assertThat(list(area + "&sort=RATING&cursor=" + CourseListCursor.rating(new java.math.BigDecimal("-1"), 0, NOW,
                UUID.randomUUID()).encode())).hasStatusOk();
        assertThat(list(area + "&sort=LATEST&cursor=" + latestCursor)).hasStatusOk();
    }

    @Test
    void needsLogin() {
        assertThat(mvc.get().uri("/api/v1/courses?swLat=33.6&swLng=126.3&neLat=33.7&neLng=126.4&sort=LATEST").exchange())
                .hasStatus(HttpStatus.UNAUTHORIZED);
    }

    private MvcTestResult list(String query) {
        return mvc.get().uri("/api/v1/courses?" + query).with(jwt()).exchange();
    }

    /** [query]의 모든 쪽을 커서로 이어 받은 코스 ID */
    private List<UUID> allPages(String query) throws Exception {
        List<UUID> all = new ArrayList<>();
        JsonNode page = data(list(query));
        all.addAll(ids(page));
        while (!page.get("nextCursor").isNull()) {
            page = data(list(query + "&cursor=" + page.get("nextCursor").asString()));
            all.addAll(ids(page));
        }
        return all;
    }

    private JsonNode data(MvcTestResult result) throws Exception {
        assertThat(result).hasStatusOk();
        return jsonMapper.readTree(result.getResponse().getContentAsString()).get("data");
    }

    private static List<UUID> ids(JsonNode data) {
        List<UUID> ids = new ArrayList<>();
        data.get("content").forEach(course -> ids.add(UUID.fromString(course.get("courseId").asString())));
        return ids;
    }

    private static void assertBadRequest(MvcTestResult result) {
        assertThat(result).hasStatus(HttpStatus.BAD_REQUEST).bodyJson().extractingPath("$.code").isEqualTo("COMMON-001");
    }

    /** 코스 통계에 리뷰 평점 합과 수를 바로 넣는다 */
    private void reviews(UUID course, int ratingSum, int reviewCount) {
        jdbcTemplate.update("INSERT INTO course.course_stats (course_id, rating_sum, review_count, created_at, updated_at) "
                + "VALUES (?, ?, ?, now(), now())", course, ratingSum, reviewCount);
    }

    /** 코스 누적 통계에 도전 수 · 조회 수 · 리뷰 수를 바로 넣는다. 평점은 리뷰마다 4점 */
    private void stats(UUID course, int challenges, int views, int reviews) {
        jdbcTemplate.update("INSERT INTO course.course_stats (course_id, challenge_count, view_count, rating_sum, review_count, "
                + "created_at, updated_at) VALUES (?, ?, ?, ?, ?, now(), now())", course, challenges, views, reviews * 4, reviews);
    }

    /** 코스 일별 통계에 그날의 도전 수 · 조회 수 · 리뷰 수를 바로 넣는다. 평점은 리뷰마다 4점 */
    private void daily(UUID course, String date, int challenges, int views, int reviews) {
        jdbcTemplate.update("INSERT INTO course.course_daily_stats (id, course_id, stat_date, challenge_count, view_count, "
                        + "rating_sum, review_count, created_at, updated_at) VALUES (?, ?, ?::date, ?, ?, ?, ?, now(), now())",
                UUID.randomUUID(), course, date, challenges, views, reviews * 4, reviews);
    }

    /** 현재 러너 수 복사본을 바로 넣는다 */
    private void runners(UUID course, int count) {
        jdbcTemplate.update("INSERT INTO course.course_active_runners (course_id, active_count, source_version, created_at, "
                + "updated_at) VALUES (?, ?, 1, now(), now())", course, count);
    }

    private UUID insert(double lat, double lng, Instant createdAt) {
        return insert(lat, lng, createdAt, "EASY", 1_000, "{}", "CUSTOM");
    }

    /** 이름과 출발점 지역을 정한 코스. 이름 키는 등록과 같게 만든다. 좌표와 지역 코드가 맞지 않아도 된다. */
    private UUID insertNamed(String name, double lat, double lng, String sigunguCode) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    expires_at, version, created_at, updated_at)
                        VALUES (?, ?, 'CUSTOM', ?, ?, 'EASY', '{}', ST_GeomFromText(?, 4326), 1000, ST_GeogFromText(?),
                                ?, ?, ?, 'ACTIVE', ?, 0, ?, ?)""",
                id, UUID.randomUUID(), CourseName.display(name), CourseName.key(name),
                "LINESTRING(%s %s, %s %s)".formatted(lng, lat, lng, lat + 0.01),
                "SRID=4326;POINT(%s %s)".formatted(lng, lat),
                sigunguCode.substring(0, 5) + "10100", sigunguCode, sigunguCode.substring(0, 2) + "00000000",
                Timestamp.from(NOW.plusSeconds(30 * 24 * 3600)), Timestamp.from(NOW), Timestamp.from(NOW));
        return id;
    }

    /** 출발점에서 북쪽으로 약 1.1km 가는 코스를 바로 넣는다. 거리 값은 확인용이라 실제 경로 길이와 다를 수 있다. 만료는 등록 30일 뒤. */
    private UUID insert(double lat, double lng, Instant createdAt, String difficulty, int distanceMeters, String tags,
                        String courseType) {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update("""
                        INSERT INTO course.courses (id, creator_id, course_type, name, name_key, difficulty, tags, route,
                                                    distance_meters, start_point, emd_code, sigungu_code, sido_code, status,
                                                    expires_at, version, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?::varchar[], ST_GeomFromText(?, 4326), ?, ST_GeogFromText(?),
                                '5011010100', '5011000000', '5000000000', 'ACTIVE', ?, 0, ?, ?)""",
                id, UUID.randomUUID(), courseType, "목록 코스 " + id, "목록코스" + id, difficulty, tags,
                "LINESTRING(%s %s, %s %s)".formatted(lng, lat, lng, lat + 0.01), distanceMeters,
                "SRID=4326;POINT(%s %s)".formatted(lng, lat),
                Timestamp.from(createdAt.plusSeconds(30 * 24 * 3600)), Timestamp.from(createdAt), Timestamp.from(createdAt));
        return id;
    }
}
