package com.wadadak.course.internal.registration;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.internal.course.CourseGeometry;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.GpsCourseRegisteredEvent;
import java.time.Clock;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

/** Publishes course-owned registration evidence atomically; never reads a run/ranking/review table. */
@Service
public class GpsSourcePublicationService {
    private final JdbcTemplate db;
    private final JsonMapper json;
    private final ApplicationEventPublisher events;
    private final Clock clock;
    GpsSourcePublicationService(JdbcTemplate db, JsonMapper json, ApplicationEventPublisher events, Clock clock) {
        this.db=db; this.json=json; this.events=events; this.clock=clock;
    }

    @Transactional
    public void publish(UUID courseId) {
        var rows=db.query("""
            SELECT s.source_segments_json,s.completion_snapshot_json,s.run_record_id,s.member_id,
                   c.name,c.distance_meters,c.version,c.status,ST_AsBinary(c.route) route
            FROM course.gps_course_sources s JOIN course.courses c ON c.id=s.course_id
            WHERE s.course_id=? FOR UPDATE OF s FOR SHARE OF c
            """,(rs,n)-> {
                if(rs.getString("completion_snapshot_json")!=null) return null;
                List<List<GeoPoint>> segments=new ArrayList<>();
                for(var segment:json.readTree(rs.getString("source_segments_json"))) {
                    List<GeoPoint> points=new ArrayList<>();
                    for(var p:segment) points.add(new GeoPoint(p.get("lat").doubleValue(),p.get("lng").doubleValue()));
                    segments.add(List.copyOf(points));
                }
                return new GpsCourseRegisteredEvent(UuidV7.create(),clock.instant(),courseId,
                    rs.getObject("member_id",UUID.class),rs.getObject("run_record_id",UUID.class),rs.getString("name"),
                    CourseGeometry.points(rs.getBytes("route")),rs.getInt("distance_meters"),rs.getLong("version"),
                    CourseStatus.valueOf(rs.getString("status")),segments);
            },courseId);
        if(rows.isEmpty() || rows.getFirst()==null) return;
        var event=rows.getFirst();
        db.update("UPDATE course.gps_course_sources SET completion_snapshot_json=? WHERE course_id=?",
                json.writeValueAsString(event),courseId);
        events.publishEvent(event);
    }

    /** Explicit, opt-in backfill. Repeated batches only emit evidence that has never been published. */
    public List<UUID> pending() {
        return db.query("SELECT course_id FROM course.gps_course_sources WHERE completion_snapshot_json IS NULL ORDER BY created_at,course_id LIMIT 50",
                (rs,n)->rs.getObject(1,UUID.class));
    }
}
