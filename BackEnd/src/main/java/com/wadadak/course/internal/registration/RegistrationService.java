package com.wadadak.course.internal.registration;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.region.RegionResolver;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseName;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.route.GeneratedRoute;
import com.wadadak.course.internal.route.RouteService;
import com.wadadak.event.course.CourseCreatedEvent;
import lombok.RequiredArgsConstructor;
import org.locationtech.jts.geom.LineString;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * 사용자 지정 코스 등록(B4-07). 한 트랜잭션이라 어느 검증에서 실패해도 일일 한도는 차감되지 않는다(성공만 차감, 정책 공통 3).
 */
@Service
@RequiredArgsConstructor
class RegistrationService {

    /** 등록일 포함 30일(정책 공통 4) */
    static final int RETENTION_DAYS = 30;

    private final RouteService routeService;
    private final SimilarityChecker similarityChecker;
    private final RegionResolver regionResolver;
    private final CourseRepository courseRepository;
    private final DailyRegistrationCountRepository dailyCountRepository;
    private final RegistrationRequestRepository requestRepository;
    private final ApplicationEventPublisher events;
    private final Clock clock;

    @Transactional
    RegisteredCourse registerCustom(UUID memberId, UUID idempotencyKey, RegisterCourseRequest request) {
        // 같은 키로 성공한 등록이 있으면 요청 내용과 관계없이 그 결과를 돌려준다. 실패한 요청은 롤백돼 기록이 없다(개발 정책 10.2 course)
        var previous = requestRepository.findByMemberIdAndIdempotencyKey(memberId, idempotencyKey);
        if (previous.isPresent()) {
            return RegisteredCourse.from(courseRepository.findById(previous.get().getCourseId()).orElseThrow());
        }

        String name = CourseName.requireValid(request.name());
        GeneratedRoute generated = routeService.generateCustom(request.anchorPoints());
        LocalDate today = today();
        consumeDailyLimit(memberId, today);

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

        Course course = courseRepository.save(Course.registerCustom(memberId, name, request.difficulty(), request.tagsOrEmpty(),
                route, generated.distanceMeters(), emdCode, expiresAt(today)));
        requestRepository.save(new RegistrationRequest(memberId, idempotencyKey, course.getId()));
        events.publishEvent(new CourseCreatedEvent(UuidV7.create(), clock.instant(), course.getId(), memberId, null));
        return RegisteredCourse.from(course);
    }

    private void consumeDailyLimit(UUID memberId, LocalDate today) {
        dailyCountRepository.insertIfAbsent(UuidV7.create(), memberId, today, CourseType.CUSTOM.name());
        DailyRegistrationCount count = dailyCountRepository
                .findByMemberIdAndRegistrationDateAndCourseType(memberId, today, CourseType.CUSTOM).orElseThrow();
        if (!count.tryIncrement(DailyLimit.of(CourseType.CUSTOM))) {
            throw new AppException(CourseErrorCode.DAILY_LIMIT_EXCEEDED);
        }
    }

    /** 유형별 오늘(Asia/Seoul) 남은 등록 수. 앱이 B3·B5·B6 진입 시 미리 막고 안내하는 데 쓴다(B4-07·B6-06). */
    @Transactional(readOnly = true)
    RegistrationQuota quota(UUID memberId) {
        LocalDate today = today();
        return new RegistrationQuota(remaining(memberId, today, CourseType.CUSTOM), remaining(memberId, today, CourseType.GPS));
    }

    private RegistrationQuota.TypeQuota remaining(UUID memberId, LocalDate today, CourseType type) {
        int used = dailyCountRepository.findRegisteredCount(memberId, today, type).orElse(0);
        int limit = DailyLimit.of(type);
        return new RegistrationQuota.TypeQuota(limit, Math.max(limit - used, 0));
    }

    private LocalDate today() {
        return LocalDate.now(clock.withZone(TimeConfig.SEOUL));
    }

    /** 등록일 포함 {@value #RETENTION_DAYS}일째 23:59:59(Asia/Seoul). 10/1 등록이면 10/30 23:59:59 */
    private static Instant expiresAt(LocalDate registeredOn) {
        return registeredOn.plusDays(RETENTION_DAYS - 1).atTime(LocalTime.of(23, 59, 59)).atZone(TimeConfig.SEOUL).toInstant();
    }
}
