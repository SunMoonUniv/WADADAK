package com.wadadak.course.internal.registration;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.region.RegionResolver;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseName;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Retention;
import com.wadadak.course.internal.route.GeneratedRoute;
import com.wadadak.course.internal.route.RouteService;
import com.wadadak.event.course.CourseCreatedEvent;
import lombok.RequiredArgsConstructor;
import org.locationtech.jts.geom.LineString;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * 코스 등록. 사용자 지정(B4-07)과 GPS 주행 등록(D4).
 * 한 트랜잭션이라 어느 검증에서 실패해도 일일 한도는 차감되지 않는다(성공만 차감, 정책 공통 3).
 */
@Service
@RequiredArgsConstructor
class RegistrationService {

    /** GPS 경로 점 수 상한. 1초에 한 점이면 약 27시간이다. 거리 상한이 아니라 요청 크기를 막는 값이다 */
    static final int MAX_GPS_SOURCE_POINTS = 100_000;

    private final RouteService routeService;
    private final SimilarityChecker similarityChecker;
    private final RegionResolver regionResolver;
    private final CourseRepository courseRepository;
    private final DailyRegistrationCountRepository dailyCountRepository;
    private final RegistrationRequestRepository requestRepository;
    private final GpsCourseSourceRepository gpsSourceRepository;
    private final ApplicationEventPublisher events;
    private final JsonMapper jsonMapper;
    private final Clock clock;

    @Transactional
    RegisteredCourse registerCustom(UUID memberId, UUID idempotencyKey, RegisterCourseRequest request) {
        Optional<RegisteredCourse> previous = previousResult(memberId, idempotencyKey);
        if (previous.isPresent()) {
            return previous.get();
        }

        String name = CourseName.requireValid(request.name());
        GeneratedRoute generated = routeService.generateCustom(request.anchorPoints());
        LocalDate today = today();
        consumeDailyLimit(memberId, today, CourseType.CUSTOM);

        Placement placement = place(name, generated);
        Course course = courseRepository.save(Course.registerCustom(memberId, name, request.difficulty(), request.tagsOrEmpty(),
                placement.route(), generated.distanceMeters(), placement.emdCode(), Retention.initialExpiresAt(today)));
        requestRepository.save(new RegistrationRequest(memberId, idempotencyKey, course.getId()));
        events.publishEvent(new CourseCreatedEvent(UuidV7.create(), clock.instant(), course.getId(), memberId, null));
        return RegisteredCourse.from(course);
    }

    /**
     * D4 코스 경로 미리보기. 저장하지 않는다. 등록과 같은 경로를 만들어 D4 지도에 보이고, 이름을 쓰기 전에 등록할 수 없는 기록을 막는다.
     * 확인 순서: 이미 등록됨(COURSE-010) → 점 2개 미만(003) → 1km 미만(004) → 빈칸을 이을 수 없음(011).
     * 유사도 · 이름 · 출발점 지역 · 일일 한도는 사용자 지정의 B3 `다음`처럼 등록 때 본다.
     */
    @Transactional(readOnly = true)
    GeneratedRoute previewGps(GpsRouteRequest request) {
        requireUnusedRunRecord(request.sourceRunRecordId());
        return gpsRoute(request.segments());
    }

    @Transactional
    RegisteredCourse registerGps(UUID memberId, UUID idempotencyKey, RegisterGpsCourseRequest request) {
        Optional<RegisteredCourse> previous = previousResult(memberId, idempotencyKey);
        if (previous.isPresent()) {
            return previous.get();
        }

        String name = CourseName.requireValid(request.name());
        GeneratedRoute generated = gpsRoute(request.segments());
        LocalDate today = today();
        consumeDailyLimit(memberId, today, CourseType.GPS);
        // 한도 행을 잠근 뒤에 본다. 같은 회원이 같은 기록으로 동시에 등록해도 하나만 된다
        requireUnusedRunRecord(request.sourceRunRecordId());

        Placement placement = place(name, generated);
        Course course = courseRepository.save(Course.registerGps(memberId, name, request.difficulty(), request.tagsOrEmpty(),
                placement.route(), generated.distanceMeters(), placement.emdCode(), Retention.initialExpiresAt(today)));
        gpsSourceRepository.save(new GpsCourseSource(course.getId(), request.sourceRunRecordId(), memberId,
                jsonMapper.writeValueAsString(request.segments())));
        requestRepository.save(new RegistrationRequest(memberId, idempotencyKey, course.getId()));
        events.publishEvent(new CourseCreatedEvent(UuidV7.create(), clock.instant(), course.getId(), memberId,
                request.sourceRunRecordId()));
        return RegisteredCourse.from(course);
    }

    /** 같은 키로 성공한 등록이 있으면 요청 내용과 관계없이 그 결과. 실패한 요청은 롤백돼 기록이 없다(개발 정책 10.2 course) */
    private Optional<RegisteredCourse> previousResult(UUID memberId, UUID idempotencyKey) {
        return requestRepository.findByMemberIdAndIdempotencyKey(memberId, idempotencyKey)
                .map(previous -> RegisteredCourse.from(courseRepository.findById(previous.getCourseId()).orElseThrow()));
    }

    private void requireUnusedRunRecord(UUID runRecordId) {
        if (gpsSourceRepository.existsByRunRecordId(runRecordId)) {
            throw new AppException(CourseErrorCode.RUN_RECORD_ALREADY_REGISTERED);
        }
    }

    /** 경로 조각을 이어 점을 줄인 경로. 빈칸 기준은 줄이기 전 원래 조각으로 본다(run 판단과 같은 입력) */
    private GeneratedRoute gpsRoute(List<List<GpsSourcePoint>> source) {
        if (source.stream().mapToLong(List::size).sum() > MAX_GPS_SOURCE_POINTS) {
            throw new AppException(CommonErrorCode.INVALID_REQUEST, "경로 점은 " + MAX_GPS_SOURCE_POINTS + "개까지 보낼 수 있습니다.");
        }
        List<List<GeoPoint>> segments = source.stream()
                .map(segment -> segment.stream().map(GpsSourcePoint::location).toList())
                .toList();
        GeneratedRoute generated = routeService.generateGps(segments);
        if (!GpsGapRule.passes(segments)) {
            throw new AppException(CourseErrorCode.GPS_ACCURACY_LOW);
        }
        return generated;
    }

    /** 이름 중복(006) → 출발점 지역(009) → 85% 유사(007) */
    private Placement place(String name, GeneratedRoute generated) {
        if (courseRepository.existsActiveByName(name)) {
            throw new AppException(CourseErrorCode.NAME_TAKEN);
        }
        GeoPoint start = generated.route().getFirst();
        String emdCode = regionResolver.resolveCode(start.lat(), start.lng())
                .orElseThrow(() -> new AppException(CourseErrorCode.START_REGION_NOT_FOUND));
        LineString route = CourseGeometry.lineString(generated.route());
        if (similarityChecker.maxSimilarity(route) >= SimilarityChecker.MAX_SIMILARITY) {
            throw new AppException(CourseErrorCode.SIMILAR_COURSE_EXISTS);
        }
        return new Placement(route, emdCode);
    }

    private record Placement(LineString route, String emdCode) {
    }

    private void consumeDailyLimit(UUID memberId, LocalDate today, CourseType type) {
        dailyCountRepository.insertIfAbsent(UuidV7.create(), memberId, today, type.name());
        DailyRegistrationCount count = dailyCountRepository
                .findByMemberIdAndRegistrationDateAndCourseType(memberId, today, type).orElseThrow();
        if (!count.tryIncrement(DailyLimit.of(type))) {
            throw new AppException(CourseErrorCode.DAILY_LIMIT_EXCEEDED);
        }
    }

    /**
     * 유형별 오늘(Asia/Seoul) 남은 등록 수와 GPS 등록에 쓴 러닝 기록.
     * 앱이 B3·B5·B6 진입 시 미리 막고 안내하고(B4-07·B6-06), B6 · 결과 화면에 `이미 등록됨`을 보이는 데 쓴다.
     */
    @Transactional(readOnly = true)
    RegistrationQuota quota(UUID memberId) {
        LocalDate today = today();
        return new RegistrationQuota(remaining(memberId, today, CourseType.CUSTOM), remaining(memberId, today, CourseType.GPS),
                gpsSourceRepository.findRunRecordIdsByMemberId(memberId));
    }

    private RegistrationQuota.TypeQuota remaining(UUID memberId, LocalDate today, CourseType type) {
        int used = dailyCountRepository.findRegisteredCount(memberId, today, type).orElse(0);
        int limit = DailyLimit.of(type);
        return new RegistrationQuota.TypeQuota(limit, Math.max(limit - used, 0));
    }

    private LocalDate today() {
        return LocalDate.now(clock.withZone(TimeConfig.SEOUL));
    }
}
