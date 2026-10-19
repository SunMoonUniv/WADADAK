package com.wadadak.course.internal.course;

import com.wadadak.common.entity.BaseEntity;
import com.wadadak.common.entity.UuidV7;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusReason;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import org.locationtech.jts.geom.LineString;
import org.locationtech.jts.geom.Point;

import java.time.Instant;
import java.util.EnumSet;
import java.util.Set;
import java.util.UUID;

@Getter
@Entity
@Table(schema = "course", name = "courses")
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Course extends BaseEntity<UUID> {

    @Id
    private UUID id;

    private UUID creatorId;

    @Enumerated(EnumType.STRING)
    private CourseType courseType;

    private String name;

    /** {@link CourseName#key(String)}. 활성 코스 중 유니크 */
    private String nameKey;

    @Enumerated(EnumType.STRING)
    private Difficulty difficulty;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.ARRAY)
    private Set<CourseTag> tags;

    private LineString route;

    private int distanceMeters;

    @Column(columnDefinition = "geography(Point,4326)")
    private Point startPoint;

    private String emdCode;
    private String sigunguCode;
    private String sidoCode;

    @Enumerated(EnumType.STRING)
    private CourseStatus status;

    @Enumerated(EnumType.STRING)
    private CourseStatusReason statusReason;

    private Instant hiddenAt;
    private Instant expiresAt;

    @Version
    private Long version;

    /**
     * 사용자 지정 코스 등록. 바로 공개된다(B4-07).
     *
     * @param route   SRID 4326. 첫 점이 출발점이 된다
     * @param emdCode 출발점의 읍·면·동 법정동 코드(10자리). 시·군·구·시·도 코드는 앞 5·2자리로 만든다
     */
    public static Course registerCustom(UUID creatorId, String name, Difficulty difficulty, Set<CourseTag> tags,
                                        LineString route, int distanceMeters, String emdCode, Instant expiresAt) {
        Course course = new Course();
        course.id = UuidV7.create();
        course.creatorId = creatorId;
        course.courseType = CourseType.CUSTOM;
        course.name = CourseName.display(name);
        course.nameKey = CourseName.key(name);
        course.difficulty = difficulty;
        course.tags = tags.isEmpty() ? EnumSet.noneOf(CourseTag.class) : EnumSet.copyOf(tags);
        course.route = route;
        course.distanceMeters = distanceMeters;
        course.startPoint = route.getStartPoint();
        course.emdCode = emdCode;
        course.sigunguCode = emdCode.substring(0, 5) + "00000";
        course.sidoCode = emdCode.substring(0, 2) + "00000000";
        course.status = CourseStatus.ACTIVE;
        course.expiresAt = expiresAt;
        return course;
    }

    public boolean isActive() {
        return status == CourseStatus.ACTIVE;
    }

    /** 공개 중인데 만료 시각이 지났다. 만료 배치가 비공개로 바꾼다 */
    public boolean isExpiredAt(Instant now) {
        return isActive() && !now.isBefore(Retention.end(expiresAt));
    }

    /**
     * 서버가 확정한 완주로 유지 기간을 연장한다(정책 공통 4 · D-10). 고정 구간마다 한 번, 현재 만료일에서 30일이다.
     * 만료 시각이 늘 마지막 구간의 끝이고 앞 구간은 모두 이미 연장했으므로, 기록 등록 시각이 마지막 구간 안일 때만 연장한다.
     * 같은 완주가 다시 오거나 같은 구간의 다른 완주가 와도 만료일이 이미 다음 구간으로 넘어가 있어 다시 연장하지 않는다.
     * 만료 뒤에 받은 완주는 완주가 만료 전이었어도, 배치가 아직 숨기지 않았어도 연장하지 않는다.
     *
     * @param registeredAt 기록 등록 시각(서버). 만료일 다음 날 00:00 이후면 연장하지 않는다
     * @param receivedAt   완주 이벤트를 받은 시각
     * @return 연장했으면 {@code true}. 공개 중이 아니거나 만료됐으면 복구 없이 {@code false}
     */
    public boolean extendByCompletion(Instant registeredAt, Instant receivedAt) {
        if (!isActive() || isExpiredAt(receivedAt) || registeredAt.isBefore(Retention.lastPeriodStart(expiresAt))
                || !registeredAt.isBefore(Retention.end(expiresAt))) {
            return false;
        }
        expiresAt = Retention.extended(expiresAt);
        return true;
    }

    /** 비공개로 바꾼다(ACTIVE → HIDDEN). 신규 노출·진입을 막고 24시간 뒤 삭제한다 */
    public void hide(CourseStatusReason reason, Instant at) {
        if (!isActive()) {
            throw new IllegalStateException("공개 중인 코스만 숨긴다: " + id + " " + status);
        }
        status = CourseStatus.HIDDEN;
        statusReason = reason;
        hiddenAt = at;
    }

    /** 삭제를 확정한다(HIDDEN → DELETED). 행은 남기고 숨긴 사유·시각은 그대로 둔다 */
    public void delete() {
        if (status != CourseStatus.HIDDEN) {
            throw new IllegalStateException("숨긴 코스만 삭제한다: " + id + " " + status);
        }
        status = CourseStatus.DELETED;
    }
}
