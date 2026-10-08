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
}
