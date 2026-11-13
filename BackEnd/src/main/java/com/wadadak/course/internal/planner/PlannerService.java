package com.wadadak.course.internal.planner;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.region.RegionResolver;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.planner.CandidateSelector.Selection;
import com.wadadak.course.internal.planner.PlanForm.Shape;
import com.wadadak.course.internal.planner.PlanForm.StartKind;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * {@link CoursePlanner} 실제 구현(정책 B3-A01~A05). {@code app.stub.course-planner: true}면 {@link PlannerStub}이 대신 뜬다.
 *
 * <p>생성은 한도를 먼저 잡고 그때부터 기한({@code app.course.planner.deadline})을 잰다. 길을 찾지 않고 끝나거나(장소 없음 · 너무 멂 ·
 * 지역 없음) 서버가 실패하면 한도를 되돌린다. 외부 호출이 길어 트랜잭션으로 묶지 않는다.
 * 서버 로그에는 단계별 시간 · 후보 수 · 사유만 남긴다. 문장 · 장소 이름 · 좌표는 남기지 않는다.
 * 문장 · 폼 · 후보(경로 점 포함)는 분석 로그 테이블({@link PlannerLogRepository})에만 남긴다(회원 ID · 현재 위치 없이).
 */
@Slf4j
@Service
@ConditionalOnProperty(name = "app.stub.course-planner", havingValue = "false", matchIfMissing = true)
class PlannerService implements CoursePlanner {

    static final int PLAN_LIMIT = 20;
    static final int PARSE_LIMIT = 50;
    /** 후보의 편의점 수: 경로에서 이 거리(m) 안 */
    static final int STORE_METERS = 50;
    /** 후보의 화장실 수: 경로에서 이 거리(m) 안. 주소로 찾은 좌표라 건물 · 공원 가운데에 찍혀 편의점보다 넓게 본다 */
    static final int TOILET_METERS = 100;

    private final PlannerRepository repository;
    private final PlannerLogRepository logs;
    private final SentenceParser parser;
    private final PlaceSearch placeSearch;
    private final RegionResolver regionResolver;
    private final CandidateGenerator generator;
    private final CandidateSelector selector;
    private final RoutingClient routing;
    private final Clock clock;
    private final Duration deadline;

    PlannerService(PlannerRepository repository, PlannerLogRepository logs, SentenceParser parser, PlaceSearch placeSearch, RegionResolver regionResolver,
                   CandidateGenerator generator, CandidateSelector selector, RoutingClient routing, Clock clock,
                   @Value("${app.course.planner.deadline}") Duration deadline) {
        this.repository = repository;
        this.logs = logs;
        this.parser = parser;
        this.placeSearch = placeSearch;
        this.regionResolver = regionResolver;
        this.generator = generator;
        this.selector = selector;
        this.routing = routing;
        this.clock = clock;
        this.deadline = deadline;
    }

    @Override
    public PlanForm parse(UUID memberId, String text) {
        if (!repository.reserve(memberId, today(), PlannerRepository.PARSE, PARSE_LIMIT)) {
            throw new AppException(CourseErrorCode.PARSE_DAILY_LIMIT_EXCEEDED);
        }
        long started = System.nanoTime();
        SentenceParser.Parsed parsed = parser.parse(text);
        logs.saveParse(memberId, text, parsed.jev(), parsed.form(), millis(started, System.nanoTime()));
        return parsed.form();
    }

    @Override
    public PlanResult plan(UUID memberId, PlanRequest request) {
        LocalDate today = today();
        if (!repository.reserve(memberId, today, PlannerRepository.PLAN, PLAN_LIMIT)) {
            throw new AppException(CourseErrorCode.PLAN_DAILY_LIMIT_EXCEEDED);
        }
        boolean counted = false;
        try {
            Outcome outcome = plan(request, clock.instant().plus(deadline));
            counted = outcome.routed();
            logs.savePlan(memberId, request, outcome.result(), outcome.placeMs(), outcome.routeMs(), outcome.selectMs());
            return outcome.result();
        } finally {
            if (!counted) {
                repository.release(memberId, today, PlannerRepository.PLAN);
            }
        }
    }

    @Override
    public PlanQuota quota(UUID memberId) {
        return new PlanQuota(PLAN_LIMIT, Math.max(0, PLAN_LIMIT - repository.used(memberId, today(), PlannerRepository.PLAN)));
    }

    private Outcome plan(PlanRequest request, Instant deadline) {
        PlanForm form = request.form();
        Integer target = request.targetMeters();
        long started = System.nanoTime();

        Places places = places(request, target);
        if (places.failure() != null) {
            long placeMs = millis(started, System.nanoTime());
            log.info("코스 자동 생성: {} 장소 {}ms {}", form.shape(), placeMs, places.failure().reason());
            return new Outcome(places.failure(), false, placeMs, null, null);
        }
        String startName = places.startName();

        long placed = System.nanoTime();
        List<RoutedPath> paths = generator.generate(form.shape(), places.start(), places.place(), target, form.prefer(), deadline);
        long routed = System.nanoTime();
        if (paths.isEmpty() && !routing.healthy()) {
            log.warn("코스 자동 생성: 길찾기 서버가 응답하지 않는다");
            throw new AppException(CommonErrorCode.INTERNAL_ERROR);
        }
        Selection selection = selector.select(form.shape(), target, paths, form.prefer(),
                line -> repository.poisNear(line, STORE_METERS, TOILET_METERS));
        PlanResult result = !selection.candidates().isEmpty() ? PlanResult.found(selection.candidates(), startName, selection.notApplied())
                : selection.allSimilarToExisting() ? PlanResult.similarExists(startName)
                : PlanResult.noCandidates(form.shape() == Shape.LOOP, startName);
        long placeMs = millis(started, placed);
        long routeMs = millis(placed, routed);
        long selectMs = millis(routed, System.nanoTime());
        log.info("코스 자동 생성: {} 장소 {}ms 길찾기 {}ms({}개) 고르기 {}ms 후보 {}개 {}", form.shape(), placeMs,
                routeMs, paths.size(), selectMs, result.candidates().size(), result.reason());
        return new Outcome(result, true, placeMs, routeMs, selectMs);
    }

    /** 출발지와 도착지 · 경유지를 찾는다. 못 찾았거나 너무 멀거나 지역 데이터 밖이면 그 안내만 돌려준다 */
    private Places places(PlanRequest request, Integer target) {
        PlanForm form = request.form();
        GeoPoint start = request.currentLocation();
        String startName = null;
        if (form.start().kind() == StartKind.PLACE) {
            String query = form.start().query().strip();
            Optional<PlaceHit> hit = find(query, request.currentLocation());
            if (hit.isEmpty()) {
                return Places.failed(PlanResult.placeNotFound(query, null));
            }
            start = hit.get().location();
            startName = hit.get().name();
        }

        GeoPoint place = null;
        String placeQuery = form.shape() == Shape.POINT_TO_POINT ? form.endQuery() : form.shape() == Shape.VIA ? form.viaQuery() : null;
        if (placeQuery != null) {
            String query = placeQuery.strip();
            Optional<PlaceHit> hit = find(query, start);
            if (hit.isEmpty()) {
                return Places.failed(PlanResult.placeNotFound(query, startName));
            }
            place = hit.get().location();
            if (PlaceRules.tooFar(form.shape(), start, place, target)) {
                String from = startName != null ? startName : "현재 위치";
                return Places.failed(PlanResult.placeTooFar(query, from, start.distanceMeters(place), startName));
            }
        }

        // 지역 데이터 밖(바다 · 국외)이면 길찾기 그래프도 없다
        if (regionResolver.resolveCode(start.lat(), start.lng()).isEmpty()) {
            return Places.failed(PlanResult.noCandidates(false, startName));
        }
        return new Places(start, startName, place, null);
    }

    private Optional<PlaceHit> find(String query, GeoPoint near) {
        return PlaceRules.pick(query, placeSearch.search(query, near), near);
    }

    private static long millis(long from, long to) {
        return (to - from) / 1_000_000;
    }

    private LocalDate today() {
        return LocalDate.now(clock.withZone(TimeConfig.SEOUL));
    }

    /**
     * @param routed  길찾기를 했는지. false면 한도를 되돌린다
     * @param routeMs 길찾기 시간. 장소에서 끝났으면 null(selectMs도 같다)
     */
    private record Outcome(PlanResult result, boolean routed, long placeMs, Long routeMs, Long selectMs) {
    }

    /**
     * @param place   편도의 도착지 또는 경유의 경유지. 한 바퀴 · 왕복은 null
     * @param failure 길을 찾지 않고 끝낼 때의 안내. 이때 나머지는 비어 있다
     */
    private record Places(GeoPoint start, String startName, GeoPoint place, PlanResult failure) {

        static Places failed(PlanResult failure) {
            return new Places(null, null, null, failure);
        }
    }
}
