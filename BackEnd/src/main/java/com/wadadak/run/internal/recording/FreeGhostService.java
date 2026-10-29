package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.run.RunErrorCode;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.ghost.GhostPlaybackBuilder;
import com.wadadak.run.internal.metrics.FreeRunCalculator;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.time.temporal.TemporalAdjusters;
import java.time.DayOfWeek;
import java.sql.Timestamp;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

/** Own free-record duels; never calls CourseApi or publishes course-start/completion events. */
@Service
class FreeGhostService {
    private final RunSessionRepository sessions;
    private final RunRecordRepository records;
    private final RunInputRepository inputs;
    private final CourseAttemptRepository attempts;
    private final DeletedRunRecordRepository deletions;
    private final WithdrawnRunMemberRepository withdrawals;
    private final RunLocks locks;
    private final FreeGhostRepository starts;
    private final JsonMapper json;
    private final JdbcTemplate db;
    private final Clock clock;
    private final GhostPlaybackBuilder builder=new GhostPlaybackBuilder();
    FreeGhostService(RunSessionRepository sessions, RunRecordRepository records, RunInputRepository inputs,
                     CourseAttemptRepository attempts, DeletedRunRecordRepository deletions,
                     WithdrawnRunMemberRepository withdrawals, RunLocks locks, FreeGhostRepository starts,
                     JsonMapper json, JdbcTemplate db, Clock clock) {
        this.sessions=sessions; this.records=records; this.inputs=inputs; this.attempts=attempts;
        this.deletions=deletions; this.withdrawals=withdrawals; this.locks=locks; this.starts=starts;
        this.json=json; this.db=db; this.clock=clock;
    }
    private void lock(UUID owner, UUID id) {
        locks.member(owner);
        if(withdrawals.existsById(owner)) notFound();
        locks.session(id);
        if(deletions.existsById(id)) notFound();
    }
    private static void notFound() { throw new AppException(RunErrorCode.NOT_FOUND); }
    private static void conflict() { throw new AppException(RunErrorCode.CONFLICT); }

    @Transactional(readOnly=true)
    public FreeGhostPreparation prepare(UUID owner, UUID id) {
        lock(owner,id);
        var session=sessions.findByIdAndMemberId(id,owner).orElseThrow(()->new AppException(RunErrorCode.NOT_FOUND));
        if(!"DONE".equals(session.getProcessing())) throw new AppException(RunErrorCode.GHOST_UNAVAILABLE);
        var record=records.findById(id).orElseThrow(()->new AppException(RunErrorCode.NOT_FOUND));
        Result source=json.readValue(record.getResultJson(),Result.class);
        GhostPlayback replay;
        if(source.course()!=null || attempts.existsById(id))
            replay=builder.unavailableReference(source,null,"NOT_FREE_RECORD");
        else if(source.metrics().distanceM()<1000)
            replay=builder.unavailableReference(source,null,"DISTANCE_BELOW_1000M");
        else {
            try {
                var raw=inputs.findAll(id);
                if(raw.isEmpty() || !Objects.equals(source.calculationVersion(),raw.getFirst().reason())
                    || (source.calculationVersion()!=null
                        && !List.of("PACE_V1","PACE_V2","PACE_V3").contains(source.calculationVersion())))
                    throw new IllegalArgumentException("Unsupported source calculation");
                var calculation=FreeRunCalculator.calculate(source.startedAt(),raw);
                if(Math.abs(calculation.metrics().distanceM()-source.metrics().distanceM())>1e-6
                    || calculation.metrics().elapsedMs()!=source.metrics().elapsedMs())
                    throw new IllegalArgumentException("Source metrics mismatch");
                List<GeoPoint> route=new ArrayList<>();
                List<Integer> breaks=new ArrayList<>();
                double length=0;
                for(var segment:calculation.samples()) {
                    if(segment.size()<2) continue;
                    if(!route.isEmpty()) breaks.add(route.size());
                    for(int i=0;i<segment.size();i++) {
                        route.add(segment.get(i).location());
                        if(i>0) length+=segment.get(i-1).location().distanceMeters(segment.get(i).location());
                    }
                }
                if(route.size()<2 || length<=0 || !Double.isFinite(length) || length>Integer.MAX_VALUE)
                    throw new IllegalArgumentException("No reference geometry");
                var reference=new CourseSnapshot(id,null,"내 자유 러닝",route,(int)Math.ceil(length),1,breaks);
                replay=builder.buildReference(source,reference,raw);
            } catch(AppException | IllegalArgumentException e) {
                replay=builder.unavailableReference(source,null,"MISSING_SOURCE_INPUTS");
            }
        }
        return new FreeGhostPreparation(replay,source.metrics().distanceM(),source.metrics().elapsedMs(),
            source.endReason(),fingerprint(replay));
    }

    private String fingerprint(GhostPlayback replay) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
            .digest(json.writeValueAsString(replay).getBytes(StandardCharsets.UTF_8))); }
        catch(java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }

    @Transactional
    public GhostStartApproval start(UUID owner, UUID id, GhostStart request) {
        lock(owner,id);
        var existing=starts.find(id);
        if(existing.isPresent()) {
            var saved=existing.get();
            if(!owner.equals(saved.owner())) notFound();
            var approval=saved.approval();
            if(!approval.sourceRecordId().equals(request.sourceRecordId())
                || !approval.startedAt().equals(request.startedAt()) || request.courseId()!=null
                || !Objects.equals(request.courseVersion(),approval.course().version())
                || !Objects.equals(saved.referenceHash(),request.referenceHash())
                || request.publicPeriod()!=null || !GhostPlaybackBuilder.FREE_VERSION.equals(request.playbackVersion())) conflict();
            return approval;
        }
        if(sessions.existsById(id) || attempts.existsById(id)) conflict();
        if(id.equals(request.sourceRecordId()) || request.startedAt()==null || request.startedAt().getNano()%1000!=0
            || request.startedAt().isAfter(clock.instant().plusSeconds(300)) || request.courseId()!=null
            || request.publicPeriod()!=null || !GhostPlaybackBuilder.FREE_VERSION.equals(request.playbackVersion()))
            throw new AppException(RunErrorCode.INVALID);
        // Ownership is established before the source session lock (same member lock order as deletion).
        sessions.findByIdAndMemberId(request.sourceRecordId(),owner).orElseThrow(()->new AppException(RunErrorCode.NOT_FOUND));
        var prepared=prepare(owner,request.sourceRecordId());
        if(!prepared.playback().eligible()) throw new AppException(RunErrorCode.GHOST_UNAVAILABLE);
        if(!prepared.referenceHash().equals(request.referenceHash())
            || !Objects.equals(request.courseVersion(),prepared.playback().course().version())) conflict();
        var r=prepared.playback().course();
        var reference=new CourseSnapshot(id,null,r.name(),r.route(),r.totalDistanceMeters(),r.version(),r.breaks());
        var now=clock.instant().truncatedTo(ChronoUnit.MICROS);
        var approval=new GhostStartApproval("GHOST_START_FREE_V1",id,request.sourceRecordId(),request.startedAt(),now,now,reference,prepared.playback());
        sessions.saveAndFlush(new RunSession(id,owner,request.startedAt()));
        starts.save(owner,prepared.referenceHash(),approval);
        return approval;
    }

    @Transactional(readOnly=true)
    public Optional<GhostStartApproval> receipt(UUID owner, UUID id) {
        lock(owner,id);
        return starts.find(id).map(saved->{ if(!owner.equals(saved.owner())) notFound(); return saved.approval(); });
    }

    @Transactional(readOnly=true)
    public FreeGhostPage candidates(UUID owner, OwnGhostPeriod period, int size, String cursor) {
        locks.member(owner);
        if(withdrawals.existsById(owner)) notFound();
        if(size<1 || size>50) throw new AppException(RunErrorCode.INVALID);
        var now=clock.instant().atZone(ZoneId.of("Asia/Seoul"));
        Instant from=switch(period) {
            case ALL -> Instant.parse("0001-01-01T00:00:00Z");
            case MONTH -> now.withDayOfMonth(1).toLocalDate().atStartOfDay(now.getZone()).toInstant();
            case WEEK -> now.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)).toLocalDate().atStartOfDay(now.getZone()).toInstant();
        };
        Instant before=Instant.parse("9999-12-31T00:00:00Z"); UUID beforeId=new UUID(-1,-1);
        String scope=period+"|"+from;
        if(cursor!=null) {
            try { var parts=cursor.split("\\|",4); if(!scope.equals(parts[0]+"|"+parts[1])) conflict();
                before=Instant.parse(parts[2]); beforeId=UUID.fromString(parts[3]); }
            catch(RuntimeException e) { throw new AppException(RunErrorCode.INVALID); }
        }
        var rows=db.query("""
            SELECT r.id,s.started_at,r.registered_at,r.summary_json FROM run.records r
            JOIN run.sessions s ON s.id=r.id
            WHERE s.member_id=? AND s.processing='DONE' AND s.started_at>=?
                AND (s.started_at,r.id)<(?,?)
                AND (r.result_json::jsonb->>'course') IS NULL
                AND NOT EXISTS (SELECT 1 FROM run.course_attempts c WHERE c.session_id=r.id)
                AND NOT EXISTS (SELECT 1 FROM run.deleted_records d WHERE d.id=r.id)
            ORDER BY s.started_at DESC,r.id DESC LIMIT ?
            """,(rs,n)->{
                var summary=json.readValue(rs.getString("summary_json"),RecordSummary.class);
                return new FreeGhostCandidate(rs.getObject("id",UUID.class),rs.getTimestamp("started_at").toInstant(),
                    rs.getTimestamp("registered_at").toInstant(),summary.endReason(),summary.metrics().distanceM(),
                    summary.metrics().elapsedMs(),summary.metrics().distanceM()>=1000);
            },owner,Timestamp.from(from),Timestamp.from(before),beforeId,size+1);
        boolean more=rows.size()>size;
        var content=List.copyOf(rows.subList(0,Math.min(size,rows.size())));
        var last=content.isEmpty()?null:content.getLast();
        return new FreeGhostPage(content,more?scope+"|"+last.startedAt()+"|"+last.id():null);
    }
}
