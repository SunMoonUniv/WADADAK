package com.wadadak.course.internal.planner;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.course.internal.planner.CandidateSelector.Selection;
import com.wadadak.course.internal.planner.PlanForm.Pref;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanResult.PlanCandidate;
import com.wadadak.course.internal.planner.PlannerRepository.PoiCounts;
import com.wadadak.course.internal.planner.RoutedPath.RoadClassSpan;
import com.wadadak.course.internal.route.RouteService;
import com.wadadak.member.MemberApi;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.locationtech.jts.geom.LineString;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Function;
import java.util.stream.IntStream;

import static com.wadadak.course.internal.planner.CandidateGenerator.destination;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/**
 * 거르기 · 순위 · 겹침(PostGIS 유사도)을 실제 DB로 확인한다. 테스트마다 다른 동네(위도)를 써서 서로 저장한 코스가 겹치지 않는다.
 * 경로는 한 변 1,250m 정사각형(5km 한 바퀴)이다.
 */
@ApplicationModuleTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class CandidateSelectorTest {

    // course만 띄워서 member 모듈이 없다. 코스 상세가 등록자 닉네임에 MemberApi를 쓰므로 가짜로 채운다
    @MockitoBean
    MemberApi memberApi;

    // 기본은 표고점 파일이 없을 때(오르막 null). 평지 · 오르막 시험만 값을 준다
    @MockitoBean
    SpotHeights spotHeights;

    @Autowired
    CandidateSelector selector;

    @Autowired
    CourseRepository courseRepository;

    @BeforeEach
    void noHeights() {
        when(spotHeights.ascentMeters(any())).thenReturn(null);
    }

    @Test
    void dropsCandidateOverlappingExistingCourse() {
        GeoPoint base = new GeoPoint(35.10, 128.10);
        List<GeoPoint> existing = square(base, 0);
        saveCourse(existing);
        List<GeoPoint> other = square(destination(base, 3_000, 90), 0);

        Selection result = select(Shape.LOOP, 5_000, List.of(path(existing), path(other)), Set.of());

        // 입력점은 EPSG:5179를 오가며 줄여 좌표 끝자리가 조금 다를 수 있다
        assertThat(result.candidates()).singleElement()
                .satisfies(c -> assertThat(c.anchorPoints().getFirst().distanceMeters(other.getFirst())).isLessThan(0.01));
        assertThat(result.allSimilarToExisting()).isFalse();
    }

    @Test
    void reportsWhenEveryPassingCandidateOverlapsExistingCourse() {
        List<GeoPoint> existing = square(new GeoPoint(35.20, 128.10), 0);
        saveCourse(existing);

        Selection result = select(Shape.LOOP, 5_000, List.of(path(existing)), Set.of());

        assertThat(result.candidates()).isEmpty();
        assertThat(result.allSimilarToExisting()).isTrue();
    }

    @Test
    void skipsCandidatesOverlappingEachOther() {
        GeoPoint base = new GeoPoint(35.30, 128.10);
        List<GeoPoint> first = square(base, 0);
        // 5m 옆으로 밀린 같은 길(20m 안이라 겹침)
        List<GeoPoint> shifted = first.stream().map(p -> destination(p, 5, 90)).toList();
        List<GeoPoint> other = square(destination(base, 3_000, 90), 0);

        Selection result = select(Shape.LOOP, 5_000, List.of(path(first), path(shifted), path(other)), Set.of());

        assertThat(result.candidates()).hasSize(2);
    }

    @Test
    void keepsOutAndBackWithinTenPercent() {
        GeoPoint base = new GeoPoint(35.40, 128.10);
        RoutedPath plus8 = outAndBack(base, 0, 2_700);   // 5.4km
        RoutedPath plus12 = outAndBack(destination(base, 3_000, 90), 0, 2_800);   // 5.6km
        RoutedPath oneKmOff = outAndBack(destination(base, 6_000, 90), 0, 400);   // 0.8km — 1km 미만

        Selection result = select(Shape.OUT_AND_BACK, 5_000, List.of(plus8, plus12, oneKmOff), Set.of());

        assertThat(result.candidates()).singleElement().satisfies(c -> assertThat(c.distanceMeters()).isEqualTo(5_400));
    }

    @Test
    void loopNeedsTargetWithinFivePercentAndLittleRetrace() {
        GeoPoint base = new GeoPoint(35.50, 128.10);
        RoutedPath tooLong = new RoutedPath(square(base, 0), 5_300, List.of());
        RoutedPath retrace = outAndBack(destination(base, 3_000, 90), 0, 2_500);

        assertThat(select(Shape.LOOP, 5_000, List.of(tooLong, retrace), Set.of()).candidates()).isEmpty();
    }

    @Test
    void appliesPreferenceWeights() {
        GeoPoint base = new GeoPoint(35.60, 128.10);
        List<GeoPoint> bigRoad = square(base, 0);
        List<GeoPoint> quiet = square(destination(base, 3_000, 90), 0);
        RoutedPath bigRoadPath = new RoutedPath(bigRoad, 5_000, List.of(new RoadClassSpan(0, bigRoad.size() - 1, "primary")));
        RoutedPath quietPath = new RoutedPath(quiet, 5_000, List.of(new RoadClassSpan(0, quiet.size() - 1, "footway")));

        List<PlanCandidate> avoid = select(Shape.LOOP, 5_000, List.of(bigRoadPath, quietPath), Set.of(Pref.AVOID_ARTERIAL)).candidates();
        assertThat(avoid).extracting(PlanCandidate::arterialRatio).containsExactly(0.0, 1.0);

        // 편의점은 큰길 쪽에만, 화장실은 조용한 길 쪽에만 있다
        Function<LineString, PoiCounts> pois = line -> line.getCoordinates()[0].y == bigRoad.getFirst().lat()
                ? new PoiCounts(2, 0) : new PoiCounts(0, 1);
        List<PlanCandidate> store = selector.select(Shape.LOOP, 5_000, List.of(quietPath, bigRoadPath), Set.of(Pref.STORE_ON_ROUTE), pois)
                .candidates();
        assertThat(store).extracting(PlanCandidate::storeCount).containsExactly(2, 0);

        List<PlanCandidate> toilet = selector.select(Shape.LOOP, 5_000, List.of(bigRoadPath, quietPath), Set.of(Pref.TOILET_ON_ROUTE), pois)
                .candidates();
        assertThat(toilet).extracting(PlanCandidate::toiletCount).containsExactly(1, 0);
    }

    @Test
    void ranksByClimbForFlatAndHilly() {
        GeoPoint base = new GeoPoint(35.65, 128.10);
        List<GeoPoint> hill = square(base, 0);
        List<GeoPoint> flat = square(destination(base, 3_000, 90), 0);
        when(spotHeights.available()).thenReturn(true);
        when(spotHeights.ascentMeters(hill)).thenReturn(120);
        when(spotHeights.ascentMeters(flat)).thenReturn(10);

        // 오르막 1km당 24m · 2m: 평지는 −48 · −4, 오르막은 +48 · +4
        assertThat(select(Shape.LOOP, 5_000, List.of(path(hill), path(flat)), Set.of(Pref.FLAT)).candidates())
                .extracting(PlanCandidate::ascentMeters).containsExactly(10, 120);
        Selection hilly = select(Shape.LOOP, 5_000, List.of(path(flat), path(hill)), Set.of(Pref.HILLY));
        assertThat(hilly.candidates().getFirst().ascentMeters()).isEqualTo(120);
        assertThat(hilly.notApplied()).isEmpty();
    }

    @Test
    void fillsNotAppliedPreferences() {
        List<GeoPoint> loop = square(new GeoPoint(35.70, 128.10), 0);

        // 표고점 파일이 없으면 평지도 반영하지 않는다
        Selection result = select(Shape.LOOP, 5_000, List.of(path(loop)),
                Set.of(Pref.FLAT, Pref.AVOID_ARTERIAL, Pref.TOILET_ON_ROUTE, Pref.PARK));

        assertThat(result.notApplied()).containsExactlyInAnyOrder(Pref.FLAT, Pref.PARK);
        assertThat(result.candidates().getFirst().ascentMeters()).isNull();
    }

    @Test
    void countsPoisOnlyForPickedCandidatesUnlessScored() {
        GeoPoint base = new GeoPoint(35.75, 128.10);
        List<RoutedPath> four = IntStream.range(0, 4).mapToObj(i -> path(square(destination(base, 3_000.0 * i, 90), 0))).toList();
        AtomicInteger calls = new AtomicInteger();
        Function<LineString, PoiCounts> pois = line -> {
            calls.incrementAndGet();
            return new PoiCounts(1, 2);
        };

        // 편의점 · 화장실을 점수에 쓰지 않으면 고른 3개만 센다
        List<PlanCandidate> plain = selector.select(Shape.LOOP, 5_000, four, Set.of(), pois).candidates();
        assertThat(plain).hasSize(3).allSatisfy(c -> {
            assertThat(c.storeCount()).isEqualTo(1);
            assertThat(c.toiletCount()).isEqualTo(2);
        });
        assertThat(calls).hasValue(3);

        // 점수에 쓰면 통과한 후보를 모두 센다
        calls.set(0);
        selector.select(Shape.LOOP, 5_000, four, Set.of(Pref.STORE_ON_ROUTE), pois);
        assertThat(calls).hasValue(4);
    }

    @Test
    void reducesLongZigzagToAtMost500Anchors() {
        // 60km 북쪽으로, 10m마다 좌우 5m씩 흔들린다(6,000점). 2m · 4m로는 흔들림이 남아 8m에서 500개 이하가 된다
        GeoPoint base = new GeoPoint(35.80, 128.10);
        List<GeoPoint> zigzag = new ArrayList<>();
        for (int i = 0; i < 6_000; i++) {
            zigzag.add(destination(destination(base, i * 10.0, 0), 5, i % 2 == 0 ? 90 : 270));
        }

        PlanCandidate candidate = select(Shape.POINT_TO_POINT, null, List.of(new RoutedPath(zigzag, 60_000, List.of())), Set.of())
                .candidates().getFirst();

        assertThat(candidate.anchorPoints()).hasSizeLessThanOrEqualTo(RouteService.MAX_ANCHOR_POINTS);
        assertThat(candidate.anchorPoints().getFirst().distanceMeters(zigzag.getFirst())).isLessThan(0.01);
    }

    private Selection select(Shape shape, Integer target, List<RoutedPath> paths, Set<Pref> prefer) {
        return selector.select(shape, target, paths, prefer, line -> new PoiCounts(0, 0));
    }

    /** 한 변 1,250m 정사각형. 변마다 50m 간격 점 */
    private static List<GeoPoint> square(GeoPoint start, int heading) {
        List<GeoPoint> points = new ArrayList<>(List.of(start));
        GeoPoint corner = start;
        for (int side = 0; side < 4; side++) {
            for (int i = 1; i <= 25; i++) {
                points.add(destination(corner, 50.0 * i, heading + 90 * side));
            }
            corner = points.getLast();
        }
        points.set(points.size() - 1, start);
        return points;
    }

    /** heading 쪽으로 meters 갔다가 같은 길로 돌아온다 */
    private static RoutedPath outAndBack(GeoPoint start, int heading, int meters) {
        List<GeoPoint> points = new ArrayList<>();
        for (int i = 0; i <= meters / 50; i++) {
            points.add(destination(start, 50.0 * i, heading));
        }
        for (int i = meters / 50 - 1; i >= 0; i--) {
            points.add(points.get(i));
        }
        return new RoutedPath(points, meters * 2, List.of());
    }

    private static RoutedPath path(List<GeoPoint> points) {
        return new RoutedPath(points, 5_000, List.of());
    }

    private void saveCourse(List<GeoPoint> route) {
        courseRepository.saveAndFlush(Course.registerCustom(UUID.randomUUID(), "기존 " + UUID.randomUUID().toString().substring(0, 8),
                Difficulty.MEDIUM, Set.of(), CourseGeometry.lineString(route), 5_000, "4420033000", Instant.parse("2027-11-10T14:59:59Z")));
    }
}
