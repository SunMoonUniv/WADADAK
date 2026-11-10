package com.wadadak.course.internal.registration;

import com.wadadak.event.run.CourseRunTrackEvent;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;
import tools.jackson.databind.json.JsonMapper;

/**
 * 완주 경로로 고도 프로필을 만든다(정책 공통 3, 정책 문서 제4부 4.1 `B1-03 고도 프로필`).
 * 그린 코스와 등록 기록에 고도가 부족했던 GPS 코스만, 공개 중일 때 받은 완주 중 고도가 충분한 첫 완주로 한 번 만들고 바꾸지 않는다.
 * 경로는 저장하지 않는다. 같은 이벤트를 다시 받아도 먼저 저장한 값을 덮지 않는다(개발 정책 5.4).
 */
@Component
@RequiredArgsConstructor
class ElevationProfileEventHandler {

    private final JdbcClient jdbc;
    private final JsonMapper json;

    @ApplicationModuleListener
    public void on(CourseRunTrackEvent event) {
        ElevationProfile profile = ElevationProfile.of(event.segments().stream()
                .map(segment -> segment.stream()
                        .map(p -> new GpsSourcePoint(p.lat(), p.lng(), p.accuracyM(), p.altitudeM(), p.altitudeAccuracyM()))
                        .toList())
                .toList());
        if (profile == null) {
            return; // 고도가 부족하다. 다음 완주로 만든다
        }
        // 등록 기록으로 만든 프로필이 있는 GPS 코스 · 공개 중이 아닌 코스 · 없는 코스는 버린다
        jdbc.sql("""
                        INSERT INTO course.completion_elevation_profiles (course_id, profile_json, created_at)
                        SELECT c.id, :profile, now() FROM course.courses c
                        WHERE c.id = :courseId AND c.status = 'ACTIVE'
                          AND NOT EXISTS (SELECT 1 FROM course.gps_course_sources s
                                          WHERE s.course_id = c.id AND s.elevation_profile_json <> 'null')
                        ON CONFLICT (course_id) DO NOTHING""")
                .param("profile", json.writeValueAsString(profile))
                .param("courseId", event.courseId())
                .update();
    }
}
