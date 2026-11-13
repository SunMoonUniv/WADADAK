package com.wadadak.course.internal.planner;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.exception.ErrorCode;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.region.RegionResolver;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.planner.CandidateSelector.Selection;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.Start;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import com.wadadak.course.internal.planner.PlanResult.PlanCandidate;
import com.wadadak.course.internal.planner.PlanResult.PlanReason;
import com.wadadak.course.internal.planner.PlannerRepository.PoiCounts;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.locationtech.jts.geom.LineString;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;

import static com.wadadak.course.internal.planner.CandidateGenerator.destination;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * 생성 흐름만 본다: 한도 · 장소 · 지역 · 길찾기 장애 · 사유. 후보 만들기 · 고르기는 {@link CandidateGeneratorTest} ·
 * {@link CandidateSelectorTest}, 검증 · 시간 환산 범위는 {@link PlannerControllerTest}가 본다.
 */
class PlannerServiceTest {

    private static final UUID MEMBER = UUID.randomUUID();
    private static final GeoPoint HERE = new GeoPoint(36.7983, 127.0746);
    /** 서울 2026-11-11 00:30. 한도 날짜는 서울 기준이다 */
    private static final Instant NOW = Instant.parse("2026-11-10T15:30:00Z");
    private static final LocalDate TODAY = LocalDate.of(2026, 11, 11);
    private static final LineString LINE = CourseGeometry.lineString(List.of(HERE, destination(HERE, 1_000, 0)));

    private final PlannerRepository repository = mock(PlannerRepository.class);
    private final SentenceParser parser = mock(SentenceParser.class);
    private final PlaceSearch placeSearch = mock(PlaceSearch.class);
    private final RegionResolver regionResolver = mock(RegionResolver.class);
    private final CandidateGenerator generator = mock(CandidateGenerator.class);
    private final CandidateSelector selector = mock(CandidateSelector.class);
    private final RoutingClient routing = mock(RoutingClient.class);
    private final PlannerService service = new PlannerService(repository, parser, placeSearch, regionResolver, generator, selector,
            routing, Clock.fixed(NOW, ZoneOffset.UTC), Duration.ofSeconds(10));

    @BeforeEach
    void setUp() {
        when(repository.reserve(any(), any(), any(), anyInt())).thenReturn(true);
        when(regionResolver.resolveCode(anyDouble(), anyDouble())).thenReturn(Optional.of("4420010100"));
        when(routing.healthy()).thenReturn(true);
        when(selector.select(any(), any(), any(), any(), any())).thenReturn(new Selection(List.of(), false, Set.of()));
    }

    // --- 정상 흐름

    @Test
    void plansFromCurrentLocation() {
        List<RoutedPath> paths = List.of(new RoutedPath(List.of(HERE, HERE), 5_000, List.of()));
        when(generator.generate(any(), any(), any(), any(), any(), any())).thenReturn(paths);
        // 가짜 고르기: 받은 편의점 · 화장실 함수로 센 수를 후보에 넣는다
        when(selector.select(any(), any(), any(), any(), any())).thenAnswer(a -> {
            Function<LineString, PoiCounts> pois = a.getArgument(4);
            return new Selection(List.of(candidate(pois.apply(LINE))), false, Set.of(Pref.PARK));
        });
        when(repository.poisNear(LINE, PlannerService.STORE_METERS, PlannerService.TOILET_METERS)).thenReturn(new PoiCounts(4, 2));

        PlanResult result = service.plan(MEMBER, current(Shape.LOOP, 5_000));

        assertThat(result.reason()).isNull();
        assertThat(result.startName()).isNull();
        assertThat(result.notApplied()).containsExactly(Pref.PARK);
        assertThat(result.candidates()).singleElement().satisfies(c -> {
            assertThat(c.storeCount()).isEqualTo(4);
            assertThat(c.toiletCount()).isEqualTo(2);
        });
        verify(repository).reserve(MEMBER, TODAY, PlannerRepository.PLAN, PlannerService.PLAN_LIMIT);
        // 기한은 한도를 잡은 때부터 10초
        verify(generator).generate(Shape.LOOP, HERE, null, 5_000, Set.of(), NOW.plusSeconds(10));
        verify(selector).select(eq(Shape.LOOP), eq(5_000), eq(paths), eq(Set.of()), any());
        verify(repository, never()).release(any(), any(), any());
        verifyNoInteractions(placeSearch);
    }

    @Test
    void searchesStartNearCurrentLocationAndEndNearStart() {
        GeoPoint campus = destination(HERE, 2_000, 0);
        GeoPoint station = destination(campus, 3_000, 90);
        when(placeSearch.search("선문대", HERE)).thenReturn(List.of(new PlaceHit("선문대학교", campus, false)));
        when(placeSearch.search("아산역", campus)).thenReturn(List.of(new PlaceHit("아산역", station, false)));

        PlanResult result = service.plan(MEMBER, new PlanRequest(new PlanForm(new Start(StartKind.PLACE, " 선문대 "),
                Shape.POINT_TO_POINT, "아산역", null, null, null, Set.of(), null), HERE, null));

        assertThat(result.startName()).isEqualTo("선문대학교");
        verify(generator).generate(eq(Shape.POINT_TO_POINT), eq(campus), eq(station), eq(null), any(), eq(NOW.plusSeconds(10)));
    }

    @Test
    void convertsTimeWithPace() {
        service.plan(MEMBER, new PlanRequest(loopFor(30), HERE, null));
        service.plan(MEMBER, new PlanRequest(loopFor(30), HERE, 300));

        // 30분 ÷ 390초/km ≈ 4.615km, 30분 ÷ 300초/km = 6km
        verify(generator).generate(eq(Shape.LOOP), any(), any(), eq(4_615), any(), any());
        verify(generator).generate(eq(Shape.LOOP), any(), any(), eq(6_000), any(), any());
    }

    // --- 사유와 한도 되돌리기

    @Test
    void placeNotFoundIsNotCounted() {
        PlanResult result = service.plan(MEMBER, new PlanRequest(new PlanForm(new Start(StartKind.PLACE, "없는 곳"),
                Shape.LOOP, null, null, 5_000, null, Set.of(), null), HERE, null));

        assertThat(result.reason()).isEqualTo(PlanReason.PLACE_NOT_FOUND);
        assertThat(result.message()).isEqualTo("'없는 곳'을 찾지 못했어요. 이름을 다시 확인해 주세요.");
        assertReleasedWithoutRouting();
    }

    @Test
    void tooFarPlaceIsNotCounted() {
        when(placeSearch.search(eq("한강"), any())).thenReturn(List.of(new PlaceHit("한강", destination(HERE, 80_000, 0), false)));

        PlanResult result = service.plan(MEMBER, new PlanRequest(new PlanForm(new Start(StartKind.CURRENT, null),
                Shape.VIA, null, "한강", 5_000, null, Set.of(), null), HERE, null));

        assertThat(result.reason()).isEqualTo(PlanReason.PLACE_TOO_FAR);
        assertThat(result.message()).isEqualTo("한강은 현재 위치에서 약 80km 떨어져 있어요. 가까운 곳을 골라 주세요.");
        assertReleasedWithoutRouting();
    }

    @Test
    void startOutsideRegionsIsNotCounted() {
        when(regionResolver.resolveCode(anyDouble(), anyDouble())).thenReturn(Optional.empty());

        PlanResult result = service.plan(MEMBER, current(Shape.LOOP, 5_000));

        assertThat(result.reason()).isEqualTo(PlanReason.NO_CANDIDATES);
        assertThat(result.message()).isEqualTo("이 근처에서는 길을 따라 코스를 만들지 못했어요.");
        assertReleasedWithoutRouting();
    }

    @Test
    void noRoadsIsCountedAndLoopSuggestsOutAndBack() {
        PlanResult loop = service.plan(MEMBER, current(Shape.LOOP, 5_000));
        PlanResult outAndBack = service.plan(MEMBER, current(Shape.OUT_AND_BACK, 5_000));

        assertThat(loop.reason()).isEqualTo(PlanReason.NO_CANDIDATES);
        assertThat(loop.message()).endsWith("왕복으로 바꿔 보세요.");
        assertThat(outAndBack.message()).isEqualTo("이 근처에서는 길을 따라 코스를 만들지 못했어요.");
        verify(repository, never()).release(any(), any(), any());
    }

    @Test
    void allSimilarToExistingIsCounted() {
        when(generator.generate(any(), any(), any(), any(), any(), any())).thenReturn(List.of(new RoutedPath(List.of(HERE, HERE), 5_000, List.of())));
        when(selector.select(any(), any(), any(), any(), any())).thenReturn(new Selection(List.of(), true, Set.of()));

        PlanResult result = service.plan(MEMBER, current(Shape.LOOP, 5_000));

        assertThat(result.reason()).isEqualTo(PlanReason.SIMILAR_EXISTS);
        assertThat(result.message()).isEqualTo("비슷한 코스가 이미 있어요. 거리나 출발지를 바꿔 보세요.");
        verify(repository, never()).release(any(), any(), any());
    }

    @Test
    void routingDownIsServerErrorAndNotCounted() {
        when(routing.healthy()).thenReturn(false);

        assertError(() -> service.plan(MEMBER, current(Shape.LOOP, 5_000)), CommonErrorCode.INTERNAL_ERROR);
        verify(repository).release(MEMBER, TODAY, PlannerRepository.PLAN);
        verifyNoInteractions(selector);
    }

    @Test
    void failureAfterReserveIsNotCounted() {
        when(selector.select(any(), any(), any(), any(), any())).thenThrow(new IllegalStateException("DB"));

        assertThatThrownBy(() -> service.plan(MEMBER, current(Shape.LOOP, 5_000))).hasMessage("DB");
        verify(repository).release(MEMBER, TODAY, PlannerRepository.PLAN);
    }

    @Test
    void planLimit() {
        when(repository.reserve(MEMBER, TODAY, PlannerRepository.PLAN, PlannerService.PLAN_LIMIT)).thenReturn(false);

        assertError(() -> service.plan(MEMBER, current(Shape.LOOP, 5_000)), CourseErrorCode.PLAN_DAILY_LIMIT_EXCEEDED);
        verifyNoInteractions(generator);
        verify(repository, never()).release(any(), any(), any());
    }

    // --- parse · quota

    @Test
    void parseCountsAndFillsForm() {
        PlanForm form = loopFor(30);
        when(parser.parse("30분 한 바퀴")).thenReturn(form);

        assertThat(service.parse(MEMBER, "30분 한 바퀴")).isSameAs(form);
        verify(repository).reserve(MEMBER, TODAY, PlannerRepository.PARSE, PlannerService.PARSE_LIMIT);
    }

    @Test
    void parseLimit() {
        when(repository.reserve(MEMBER, TODAY, PlannerRepository.PARSE, PlannerService.PARSE_LIMIT)).thenReturn(false);

        assertError(() -> service.parse(MEMBER, "30분 한 바퀴"), CourseErrorCode.PARSE_DAILY_LIMIT_EXCEEDED);
        verifyNoInteractions(parser);
    }

    @Test
    void quotaCountsTodaysPlans() {
        when(repository.used(MEMBER, TODAY, PlannerRepository.PLAN)).thenReturn(3);
        assertThat(service.quota(MEMBER)).isEqualTo(new CoursePlanner.PlanQuota(20, 17));

        when(repository.used(MEMBER, TODAY, PlannerRepository.PLAN)).thenReturn(25);
        assertThat(service.quota(MEMBER).remaining()).isZero();
    }

    private void assertReleasedWithoutRouting() {
        verify(repository).release(MEMBER, TODAY, PlannerRepository.PLAN);
        verifyNoInteractions(generator, selector);
    }

    private static void assertError(Runnable call, ErrorCode code) {
        assertThatThrownBy(call::run).isInstanceOfSatisfying(AppException.class, e -> assertThat(e.getErrorCode()).isEqualTo(code));
    }

    private static PlanRequest current(Shape shape, int distanceM) {
        return new PlanRequest(new PlanForm(new Start(StartKind.CURRENT, null), shape, null, null, distanceM, null, Set.of(), null),
                HERE, null);
    }

    private static PlanForm loopFor(int minutes) {
        return new PlanForm(new Start(StartKind.CURRENT, null), Shape.LOOP, null, null, null, minutes, Set.of(), null);
    }

    private static PlanCandidate candidate(PoiCounts pois) {
        return new PlanCandidate(List.of(HERE), 5_000, 0.01, 0.1, pois.stores(), pois.toilets(), null, null, null, null);
    }
}
