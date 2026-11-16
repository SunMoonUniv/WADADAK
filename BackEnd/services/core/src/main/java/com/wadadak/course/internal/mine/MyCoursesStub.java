package com.wadadak.course.internal.mine;

import com.wadadak.common.config.TimeConfig;
import com.wadadak.common.exception.AppException;
import com.wadadak.common.exception.CommonErrorCode;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.stub.StubImplementation;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.course.CourseName;
import com.wadadak.course.internal.course.CourseTag;
import com.wadadak.course.internal.course.CourseType;
import com.wadadak.course.internal.course.Difficulty;
import com.wadadak.course.internal.course.Retention;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusReason;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.UUID;

/**
 * 내 코스 스텁({@code app.stub.course-mine: true}). 피그마 G4 카드 세 개(성북천 · 한강 · 개운산)에 공개 코스 둘과 삭제 예정 코스 하나를 더해,
 * 위 칸이 피그마처럼 등록 코스 5개 · 누적 주행 1,480회 · 만료 임박 1개가 된다. 날짜는 오늘(Asia/Seoul)에서 센다.
 * <ul>
 *     <li>누가 불러도 같은 코스를 준다. 수정 · 삭제는 저장하지 않고 바뀐 카드 값만 돌려준다</li>
 *     <li>수정: 다른 공개 스텁 코스 이름이면 COURSE-006, 삭제 예정 코스(안암)는 COURSE-002</li>
 *     <li>{@link #OTHERS_COURSE_ID}는 남의 코스(COMMON-003), 그 밖의 ID는 없는 코스(COURSE-001)</li>
 *     <li>스텁 코스는 DB에 없어 B1 상세 · 리뷰 요약은 없는 코스로 답한다</li>
 * </ul>
 */
@Component
@ConditionalOnProperty(name = "app.stub.course-mine", havingValue = "true")
@RequiredArgsConstructor
class MyCoursesStub implements MyCourses, StubImplementation {

    static final UUID SEONGBUK_ID = UUID.fromString("00000000-0000-0000-0000-000000000101");
    static final UUID HANGANG_ID = UUID.fromString("00000000-0000-0000-0000-000000000102");
    static final UUID GAEUNSAN_ID = UUID.fromString("00000000-0000-0000-0000-000000000103");
    static final UUID JEONGNEUNG_ID = UUID.fromString("00000000-0000-0000-0000-000000000104");
    static final UUID BUGAK_ID = UUID.fromString("00000000-0000-0000-0000-000000000105");
    static final UUID ANAM_ID = UUID.fromString("00000000-0000-0000-0000-000000000106");
    static final UUID OTHERS_COURSE_ID = UUID.fromString("00000000-0000-0000-0000-000000000003");

    private static final LocalTime LAST_SECOND = LocalTime.of(23, 59, 59);

    private static final List<GeoPoint> SEONGBUK = List.of(new GeoPoint(37.5925, 126.9990), new GeoPoint(37.5893, 127.0068),
            new GeoPoint(37.5860, 127.0140), new GeoPoint(37.5838, 127.0200));
    private static final List<GeoPoint> HANGANG = List.of(new GeoPoint(37.5290, 127.0520), new GeoPoint(37.5265, 127.0650),
            new GeoPoint(37.5300, 127.0800), new GeoPoint(37.5350, 127.0950));
    private static final List<GeoPoint> GAEUNSAN = List.of(new GeoPoint(37.5940, 127.0240), new GeoPoint(37.5975, 127.0280),
            new GeoPoint(37.5990, 127.0330), new GeoPoint(37.5955, 127.0350));
    private static final List<GeoPoint> JEONGNEUNG = List.of(new GeoPoint(37.6040, 127.0100), new GeoPoint(37.5980, 127.0230),
            new GeoPoint(37.5900, 127.0330));
    private static final List<GeoPoint> BUGAK = List.of(new GeoPoint(37.5960, 126.9800), new GeoPoint(37.5990, 126.9870),
            new GeoPoint(37.5950, 126.9950));
    private static final List<GeoPoint> ANAM = List.of(new GeoPoint(37.5860, 127.0290), new GeoPoint(37.5880, 127.0330));

    private final Clock clock;

    @Override
    public CursorSlice<MyCourseItem> list(UUID memberId, Cursorable page) {
        return CursorSlice.ofOffset(courses(), page);
    }

    @Override
    public MyCourseSummary summary(UUID memberId) {
        Instant soonBefore = Retention.expiringSoonBefore(today());
        List<MyCourseItem> active = courses().stream().filter(course -> course.status() == CourseStatus.ACTIVE).toList();
        return new MyCourseSummary(active.size(), active.stream().mapToInt(MyCourseItem::completionCount).sum(),
                (int) active.stream().filter(course -> course.expiresAt().isBefore(soonBefore)).count());
    }

    @Override
    public MyCourseItem edit(UUID memberId, UUID courseId, EditCourseRequest request) {
        String name = CourseName.requireValid(request.name());
        MyCourseItem course = find(courseId);
        if (course.status() != CourseStatus.ACTIVE) {
            throw new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE);
        }
        String key = CourseName.key(name);
        if (courses().stream().anyMatch(other -> other.status() == CourseStatus.ACTIVE && !other.courseId().equals(courseId)
                && CourseName.key(other.name()).equals(key))) {
            throw new AppException(CourseErrorCode.NAME_TAKEN);
        }
        return new MyCourseItem(courseId, name, course.courseType(), request.difficulty(), request.tagsOrEmpty().stream().sorted().toList(),
                course.route(), course.status(), course.statusReason(), course.expiresAt(), course.deleteAt(),
                course.completionCount(), course.lastCompletedOn());
    }

    @Override
    public MyCourseItem delete(UUID memberId, UUID courseId) {
        MyCourseItem course = find(courseId);
        if (course.status() != CourseStatus.ACTIVE) {
            return course;
        }
        return new MyCourseItem(courseId, course.name(), course.courseType(), course.difficulty(), course.tags(), course.route(),
                CourseStatus.HIDDEN, CourseStatusReason.USER_DELETED, course.expiresAt(), clock.instant().plus(Retention.DELETE_AFTER),
                course.completionCount(), course.lastCompletedOn());
    }

    private MyCourseItem find(UUID courseId) {
        if (OTHERS_COURSE_ID.equals(courseId)) {
            throw new AppException(CommonErrorCode.FORBIDDEN);
        }
        return courses().stream().filter(course -> course.courseId().equals(courseId)).findFirst()
                .orElseThrow(() -> new AppException(CourseErrorCode.COURSE_NOT_FOUND));
    }

    /** 만료 임박(성북천 D-1)이 먼저, 나머지는 최근 등록순으로 놓았다. 만료일 · 최근 주행은 유지 기간 규칙(30일 구간 · 완주 연장)에 맞춘 값이다 */
    private List<MyCourseItem> courses() {
        LocalDate today = today();
        return List.of(
                active(SEONGBUK_ID, "성북천 벚꽃길 3K", CourseType.CUSTOM, Difficulty.EASY,
                        List.of(CourseTag.FLAT, CourseTag.SHADE, CourseTag.RESTROOM), SEONGBUK, today.plusDays(1), 214, today.minusDays(29)),
                active(HANGANG_ID, "한강 야경 5K", CourseType.GPS, Difficulty.MEDIUM,
                        List.of(CourseTag.FLAT, CourseTag.RIVERSIDE, CourseTag.NIGHT_LIGHT), HANGANG, today.plusDays(30), 1_204, today),
                active(GAEUNSAN_ID, "개운산 숲길 4K", CourseType.CUSTOM, Difficulty.HARD,
                        List.of(CourseTag.UPHILL, CourseTag.SHADE), GAEUNSAN, today.plusDays(29), 9, today.minusDays(1)),
                active(JEONGNEUNG_ID, "정릉천 물길 5K", CourseType.GPS, Difficulty.EASY,
                        List.of(CourseTag.SHADE, CourseTag.RIVERSIDE), JEONGNEUNG, today.plusDays(19), 41, today.minusDays(12)),
                active(BUGAK_ID, "북악산 둘레길 6K", CourseType.CUSTOM, Difficulty.HARD,
                        List.of(CourseTag.UPHILL), BUGAK, today.plusDays(14), 12, today.minusDays(20)),
                // 어제 만료돼 오늘 00:00에 비공개, 내일 00:00에 삭제된다
                new MyCourseItem(ANAM_ID, "안암 골목길 2K", CourseType.GPS, Difficulty.EASY, List.of(), ANAM,
                        CourseStatus.HIDDEN, CourseStatusReason.EXPIRED, lastSecond(today.minusDays(1)),
                        today.atStartOfDay(TimeConfig.SEOUL).toInstant().plus(Retention.DELETE_AFTER), 3, today.minusDays(45)));
    }

    private static MyCourseItem active(UUID id, String name, CourseType type, Difficulty difficulty, List<CourseTag> tags,
                                       List<GeoPoint> route, LocalDate expiresOn, int completions, LocalDate lastCompletedOn) {
        return new MyCourseItem(id, name, type, difficulty, tags, route, CourseStatus.ACTIVE, null, lastSecond(expiresOn), null,
                completions, lastCompletedOn);
    }

    private static Instant lastSecond(LocalDate day) {
        return day.atTime(LAST_SECOND).atZone(TimeConfig.SEOUL).toInstant();
    }

    private LocalDate today() {
        return LocalDate.ofInstant(clock.instant(), TimeConfig.SEOUL);
    }
}
