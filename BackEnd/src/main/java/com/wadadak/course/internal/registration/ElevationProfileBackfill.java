package com.wadadak.course.internal.registration;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;
import java.util.UUID;

/**
 * 고도 프로필 열을 넣기 전에 등록한 GPS 코스의 프로필을 저장해 둔 원본으로 만든다(정책 문서 제4부 4.1 `B1-03 고도 프로필`).
 * 서버가 켜질 때 아직 만들지 않은 코스(열이 NULL)만 본다. 고도가 부족한 코스도 JSON null을 써서 다음에는 보지 않는다.
 * 인스턴스 여러 대가 같이 돌아도 원본이 같아 같은 값이고, 먼저 쓴 값을 덮지 않는다.
 */
@Slf4j
@Component
@RequiredArgsConstructor
class ElevationProfileBackfill {

    private static final TypeReference<List<List<GpsSourcePoint>>> SEGMENTS = new TypeReference<>() {
    };

    private final JdbcClient jdbc;
    private final JsonMapper json;

    @EventListener(ApplicationReadyEvent.class)
    public void fill() {
        List<UUID> courseIds = jdbc.sql("SELECT course_id FROM course.gps_course_sources WHERE elevation_profile_json IS NULL")
                .query(UUID.class)
                .list();
        for (UUID courseId : courseIds) {
            // 한 코스를 만들지 못해도 다른 코스는 채우고 서버도 그대로 켠다
            try {
                String source = jdbc.sql("SELECT source_segments_json FROM course.gps_course_sources WHERE course_id = ?")
                        .param(courseId)
                        .query(String.class)
                        .single();
                String profile = json.writeValueAsString(ElevationProfile.of(json.readValue(source, SEGMENTS)));
                jdbc.sql("UPDATE course.gps_course_sources SET elevation_profile_json = ? WHERE course_id = ? AND elevation_profile_json IS NULL")
                        .params(profile, courseId)
                        .update();
            } catch (RuntimeException e) {
                log.warn("고도 프로필을 만들지 못했다. 서버가 다시 켜질 때 또 본다 courseId={}", courseId, e);
            }
        }
    }
}
