package com.wadadak.run.internal.recording;

import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.exception.AppException;
import com.wadadak.event.course.CourseStatus;
import com.wadadak.event.course.CourseStatusChangedEvent;
import com.wadadak.event.course.GpsCourseRegisteredEvent;
import com.wadadak.event.run.GpsSourceLinkedEvent;
import com.wadadak.event.run.GpsSourceUnlinkedEvent;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.FullSessionInputs;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.judging.CourseJudge;
import com.wadadak.run.internal.metrics.FreeRunCalculator;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

/** Policy common 3-1. Own-schema evidence and a separate course performance; never rewrites a run result. */
@Service
class GpsSourceLinkService {
    static final String POLICY = "GPS_SOURCE_COMPLETION_V1";
    private final JdbcTemplate db;
    private final JsonMapper json;
    private final RunLocks locks;
    private final RunSessionRepository sessions;
    private final RunRecordRepository records;
    private final RunInputRepository inputs;
    private final DeletedRunRecordRepository deletions;
    private final WithdrawnRunMemberRepository withdrawals;
    private final ApplicationEventPublisher events;
    private final Clock clock;

    GpsSourceLinkService(JdbcTemplate db,JsonMapper json,RunLocks locks,RunSessionRepository sessions,
            RunRecordRepository records,RunInputRepository inputs,DeletedRunRecordRepository deletions,
            WithdrawnRunMemberRepository withdrawals,ApplicationEventPublisher events,Clock clock) {
        this.db=db;this.json=json;this.locks=locks;this.sessions=sessions;this.records=records;
        this.inputs=inputs;this.deletions=deletions;this.withdrawals=withdrawals;this.events=events;this.clock=clock;
    }

    @Transactional
    public void receive(GpsCourseRegisteredEvent e) {
        locks.member(e.creatorId()); locks.session(e.sourceRunRecordId());
        db.update("""
            INSERT INTO run.gps_source_links(source_record_id,course_id,member_id,registration_event_id,snapshot_json,status)
            VALUES (?,?,?,?,?,'PENDING') ON CONFLICT(source_record_id) DO NOTHING
            """,e.sourceRunRecordId(),e.courseId(),e.creatorId(),e.eventId(),json.writeValueAsString(e));
        process(e.sourceRunRecordId());
    }

    @Transactional
    public void process(UUID id) {
        var evidence=db.query("SELECT snapshot_json FROM run.gps_source_links WHERE source_record_id=? AND status='PENDING'",
                (r,n)->json.readValue(r.getString(1),GpsCourseRegisteredEvent.class),id);
        if(evidence.isEmpty()) return;
        var e=evidence.getFirst();
        locks.member(e.creatorId()); locks.session(id);
        // The pending list and first read may race a deletion or another worker.
        if(!Boolean.TRUE.equals(db.queryForObject("SELECT status='PENDING' FROM run.gps_source_links WHERE source_record_id=?",
                Boolean.class,id))) return;
        if(withdrawals.existsById(e.creatorId())) { reject(id,"MEMBER_WITHDRAWN");return; }
        if(deletions.existsById(id)) { reject(id,"SOURCE_DELETED");return; }
        if(e.status()!=CourseStatus.ACTIVE || Boolean.TRUE.equals(db.queryForObject("""
                SELECT EXISTS(SELECT 1 FROM run.gps_course_status_copies WHERE course_id=? AND status<>'ACTIVE')
                """,Boolean.class,e.courseId()))) {reject(id,"COURSE_UNAVAILABLE");return;}
        var session=sessions.findById(id).orElse(null);
        if(session==null) {reject(id,"SOURCE_NOT_FOUND");return;}
        if(!session.getMemberId().equals(e.creatorId())) {reject(id,"SOURCE_OWNER_MISMATCH");return;}
        if(!"DONE".equals(session.getProcessing())) {
            if("FAILED".equals(session.getProcessing())) reject(id,"SOURCE_PROCESSING_FAILED");
            else db.update("UPDATE run.gps_source_links SET failure='SOURCE_PROCESSING',updated_at=now() WHERE source_record_id=?",id);
            return;
        }
        var record=records.findById(id).orElse(null);
        if(record==null) {reject(id,"SOURCE_NOT_FOUND");return;}
        Result source=json.readValue(record.getResultJson(),Result.class);
        if(source.course()!=null) {reject(id,"SOURCE_IS_COURSE_RUN");return;}
        if(source.metrics().distanceM()<1000 || e.distanceMeters()<1000 || e.route().size()<2 || e.sourceSegments().isEmpty()) {
            reject(id,"SOURCE_REGISTRATION_INVALID");return;
        }
        var raw=inputs.findAll(id);
        FreeRunCalculator.Calculation calculation;
        try {calculation=FreeRunCalculator.calculate(source.startedAt(),raw);}
        catch(AppException | IllegalArgumentException | ArithmeticException ex) {reject(id,"SOURCE_INPUTS_UNAVAILABLE");return;}
        if(Math.abs(calculation.metrics().distanceM()-source.metrics().distanceM())>1e-6
                || calculation.metrics().elapsedMs()!=source.metrics().elapsedMs()
                || !calculation.endedAt().equals(source.endedAt())) {reject(id,"SOURCE_RESULT_MISMATCH");return;}
        var actual=calculation.samples().stream().map(s->s.stream().map(p->p.location()).toList()).toList();
        if(!actual.equals(e.sourceSegments())) {reject(id,"SOURCE_ROUTE_MISMATCH");return;}

        // Only the actual recognized distance/review eligibility is judged; automatic completion is NOT gated on it.
        var full=FullSessionInputs.of(raw);
        var judgement=new CourseJudge().analyze(e.route(),List.of(),full).judgement();
        long duration=source.metrics().elapsedMs();
        var performance=new GpsSourceLinkedEvent(UuidV7.create(),clock.instant(),id,e.creatorId(),e.courseId(),
                Math.toIntExact(duration/1000),e.distanceMeters(),judgement.recognizedM(),judgement.progressPercent(),
                judgement.reviewEligible(),source.endedAt(),source.startedAt(),source.endedAt(),source.registeredAt(),POLICY);
        db.update("""
            UPDATE run.gps_source_links SET status='LINKED',failure=NULL,performance_json=?,registered_at=?,
                completed_at=?,course_elapsed_seconds=?,elapsed_ms=?,linked_at=?,updated_at=now() WHERE source_record_id=?
            """,json.writeValueAsString(performance),Timestamp.from(source.registeredAt()),Timestamp.from(source.endedAt()),
                duration/1000,duration,Timestamp.from(clock.instant()),id);
        events.publishEvent(performance);
    }

    private void reject(UUID id,String reason) {
        db.update("UPDATE run.gps_source_links SET status='REJECTED',failure=?,snapshot_json=NULL,updated_at=now() WHERE source_record_id=?",reason,id);
    }

    /** Caller holds the existing member/session locks. Tombstones survive removal of the original record. */
    void remove(UUID owner,UUID id,String reason) {
        var performance=db.query("SELECT performance_json FROM run.gps_source_links WHERE source_record_id=? AND member_id=? AND status='LINKED'",
                (r,n)->json.readValue(r.getString(1),GpsSourceLinkedEvent.class),id,owner);
        db.update("""
            UPDATE run.gps_source_links SET status='REMOVED',failure=?,snapshot_json=NULL,performance_json=NULL,updated_at=now()
            WHERE source_record_id=? AND member_id=? AND status IN ('PENDING','LINKED')
            """,reason,id,owner);
        if(!performance.isEmpty())
            events.publishEvent(new GpsSourceUnlinkedEvent(UuidV7.create(),clock.instant(),performance.getFirst(),reason));
    }

    record Evidence(GpsCourseRegisteredEvent registration,GpsSourceLinkedEvent performance) {}
    Optional<Evidence> linked(UUID owner,UUID id) {
        return db.query("SELECT snapshot_json,performance_json FROM run.gps_source_links WHERE source_record_id=? AND member_id=? AND status='LINKED'",
                (r,n)->new Evidence(json.readValue(r.getString(1),GpsCourseRegisteredEvent.class),
                        json.readValue(r.getString(2),GpsSourceLinkedEvent.class)),id,owner).stream().findFirst();
    }

    @Transactional(readOnly=true)
    public GpsSourceLinkStatus status(UUID owner,UUID id) {
        sessions.findByIdAndMemberId(id,owner).orElseThrow(()->new AppException(RunErrorCode.NOT_FOUND));
        return db.query("SELECT course_id,status,failure,linked_at FROM run.gps_source_links WHERE source_record_id=? AND member_id=?",
            (r,n)->new GpsSourceLinkStatus(r.getObject(1,UUID.class),r.getString(2),r.getString(3),
                r.getTimestamp(4)==null?null:r.getTimestamp(4).toInstant()),id,owner).stream().findFirst()
            .orElse(new GpsSourceLinkStatus(null,"NOT_RECEIVED",null,null));
    }
    @Transactional(readOnly=true)
    public List<UUID> pending() {
        return db.query("SELECT source_record_id FROM run.gps_source_links WHERE status='PENDING' ORDER BY created_at LIMIT 50",
                (r,n)->r.getObject(1,UUID.class));
    }
    @Transactional
    public void courseStatus(CourseStatusChangedEvent e) {
        db.update("""
            INSERT INTO run.gps_course_status_copies AS c(course_id,status,source_version) VALUES (?,?,?)
            ON CONFLICT(course_id) DO UPDATE SET status=EXCLUDED.status,source_version=EXCLUDED.source_version
            WHERE c.source_version<EXCLUDED.source_version
            """,e.courseId(),e.status().name(),e.version());
    }
}
