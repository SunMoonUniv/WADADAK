package com.wadadak.course.internal.detail;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.CourseErrorCode;
import com.wadadak.course.internal.course.Course;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.course.internal.course.CourseRepository;
import com.wadadak.course.internal.route.RouteService;
import com.wadadak.member.MemberApi;
import com.wadadak.member.MemberProfile;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * 코스 상세 조회(B1).
 *
 * <p>트랜잭션을 걸지 않았다. 조회만 하고, 중간에 member 모듈을 부르기 때문이다.
 * 나중에 member가 다른 서버가 되면 그 호출이 네트워크를 기다리는데, 트랜잭션 안이면 그동안 DB 커넥션을 쥐고 있게 된다(개발 정책 4.4).
 * 코스는 지연 로딩하는 값이 없어 트랜잭션 없이 읽어도 된다.
 */
@Slf4j
@Service
@RequiredArgsConstructor
class CourseDetailService {

    private final CourseRepository courseRepository;
    private final RouteService routeService;
    private final MemberApi memberApi;

    /**
     * @throws AppException {@link CourseErrorCode#COURSE_NOT_FOUND} — 없는 코스,
     *                      {@link CourseErrorCode#COURSE_NOT_AVAILABLE} — 비공개 · 삭제된 코스(B1-04 신규 상세 진입 차단)
     */
    CourseDetail detail(UUID courseId) {
        Course course = courseRepository.findById(courseId)
                .orElseThrow(() -> new AppException(CourseErrorCode.COURSE_NOT_FOUND));
        if (!course.isActive()) {
            throw new AppException(CourseErrorCode.COURSE_NOT_AVAILABLE);
        }
        List<GeoPoint> route = CourseGeometry.points(course.getRoute());
        return new CourseDetail(course.getId(), course.getName(), course.getCourseType(), course.getDifficulty(),
                course.getTags().stream().sorted().toList(), course.getDistanceMeters(), route,
                routeService.distanceMarkers(route), course.getExpiresAt(), nickname(course.getCreatorId()));
    }

    /** 표시용이라 회원 정보를 받지 못해도 상세는 그대로 돌려준다(개발 정책 4.4). */
    private String nickname(UUID creatorId) {
        try {
            return memberApi.getProfiles(Set.of(creatorId)).stream()
                    .filter(profile -> profile.memberId().equals(creatorId))
                    .map(MemberProfile::nickname)
                    .findFirst()
                    .orElse(null);
        } catch (RuntimeException e) {
            log.warn("등록자 프로필 조회 실패. 닉네임 없이 코스 상세를 돌려준다", e);
            return null;
        }
    }
}
