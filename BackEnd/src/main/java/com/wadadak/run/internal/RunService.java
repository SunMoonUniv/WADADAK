package com.wadadak.run.internal;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.event.run.RunRecordDeletedEvent;
import org.springframework.context.ApplicationEventPublisher;
import java.time.Clock;
import com.wadadak.run.RunContracts.*;
import com.wadadak.run.RunErrorCode;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

@Service
class RunService {
    private final JdbcTemplate db;
    private final JsonMapper json;
    private final ApplicationEventPublisher events;
    private final Clock clock;
    static final String POLICY_VERSION = "2026-10-14";
    RunService(JdbcTemplate db, JsonMapper json, ApplicationEventPublisher events, Clock clock) {
        this.db=db; this.json=json; this.events=events; this.clock=clock;
    }
    private void lockMember(UUID member) {
        db.query("SELECT pg_advisory_xact_lock(hashtextextended(?::text,0))", (rs,n)->true, "run-member:"+member);
    }
    private boolean withdrawn(UUID member) {
        return db.queryForObject("SELECT count(*) FROM run.withdrawn_members WHERE member_id=?",Long.class,member)>0;
    }
    private void ensureActiveMember(UUID member) {
        if (withdrawn(member)) throw new AppException(RunErrorCode.NOT_FOUND);
    }
    @Transactional
    public void withdraw(UUID member, Instant withdrawnAt) {
        lockMember(member);
        db.update("INSERT INTO run.withdrawn_members(member_id,withdrawn_at) VALUES (?,?) ON CONFLICT DO NOTHING", member, Timestamp.from(withdrawnAt));
        for (UUID id : db.query("SELECT id FROM run.sessions WHERE member_id=? ORDER BY id", (rs,n)->rs.getObject(1,UUID.class),member)) {
            lock(id);
            deleteStored(member,id);
        }
    }
    record Session(UUID id, UUID owner, Instant startedAt, Long finalSeq, String processing, String failure) {}
    private Session session(UUID owner, UUID id, boolean lock) {
        List<Session> rows=db.query("SELECT * FROM run.sessions WHERE id=? AND member_id=?"+(lock?" FOR UPDATE":""),
            (rs,n)->new Session(id, owner, rs.getTimestamp("started_at").toInstant(),
                rs.getObject("final_seq",Long.class),rs.getString("processing"),rs.getString("failure")),id,owner);
        if(rows.isEmpty()) throw new AppException(RunErrorCode.NOT_FOUND);
        return rows.getFirst();
    }
    private void lock(UUID id) {
        db.query("SELECT pg_advisory_xact_lock(hashtextextended(?::text,0))", (rs,n)->true, id.toString());
    }
    private void ensureNotDeleted(UUID id) {
        if (db.queryForObject("SELECT count(*) FROM run.deleted_records WHERE id=?",Long.class,id)>0)
            throw new AppException(RunErrorCode.NOT_FOUND);
    }
    @Transactional
    public Deleted delete(UUID owner, UUID id) {
        lockMember(owner); ensureActiveMember(owner); lock(id);
        return deleteStored(owner,id);
    }
    private Deleted deleteStored(UUID owner, UUID id) {
        List<UUID> owners = db.query("SELECT member_id FROM run.sessions WHERE id=? UNION SELECT member_id FROM run.deleted_records WHERE id=?", (rs,n)->rs.getObject(1,UUID.class),id,id);
        if (owners.stream().anyMatch(value -> !value.equals(owner))) throw new AppException(RunErrorCode.NOT_FOUND);
        List<Result> registered = db.query("SELECT result_json FROM run.records WHERE id=?", (rs,n)->json.readValue(rs.getString(1),Result.class),id);
        if (!registered.isEmpty()) {
            Result r=registered.getFirst();
            events.publishEvent(new RunRecordDeletedEvent(UuidV7.create(),clock.instant(),id,owner,null,false,
                r.metrics().distanceM(),0,r.startedAt(),r.endedAt(),r.registeredAt()));
        }
        db.update("INSERT INTO run.deleted_records(id,member_id) VALUES (?,?) ON CONFLICT DO NOTHING",id,owner);
        db.update("DELETE FROM run.records WHERE id=?",id);
        db.update("DELETE FROM run.inputs WHERE session_id=?",id);
        db.update("DELETE FROM run.sessions WHERE id=?",id);
        return new Deleted(id,true);
    }
    @Transactional
    public Status prepare(UUID owner, UUID id, Prepare request) {
        lockMember(owner); ensureActiveMember(owner); lock(id); ensureNotDeleted(id);
        if(request.startedAt()==null || !"FREE".equals(request.mode()) || request.startedAt().isAfter(clock.instant().plusSeconds(300))) invalid();
        db.update("INSERT INTO run.sessions(id,member_id,started_at,processing) VALUES (?,?,?,'PREPARED') ON CONFLICT DO NOTHING",
            id,owner,Timestamp.from(request.startedAt()));
        Session s=session(owner,id,true);
        if(!s.startedAt().equals(request.startedAt())) throw new AppException(RunErrorCode.CONFLICT);
        return statusOf(s);
    }
    @Transactional
    public Status upload(UUID owner, UUID id, Upload request) {
        lockMember(owner); ensureActiveMember(owner); lock(id); ensureNotDeleted(id);
        Session s=session(owner,id,true);
        if(s.finalSeq()!=null && s.finalSeq()!=request.finalSeq()) throw new AppException(RunErrorCode.CONFLICT);
        for(Input p:request.inputs()) {
            if(p.seq()>request.finalSeq() || p.elapsedMs()>7L*86400000 ||
                (p.kind()==Kind.GPS && (p.location()==null || p.accuracyM()==null)) ||
                (p.accuracyM()!=null && (!Double.isFinite(p.accuracyM()) || p.accuracyM()<0)) ||
                (p.altitudeM()!=null && (!Double.isFinite(p.altitudeM()) || p.kind()!=Kind.GPS)) ||
                (p.altitudeAccuracyM()!=null && (!Double.isFinite(p.altitudeAccuracyM()) || p.altitudeAccuracyM()<0 || p.altitudeM()==null))) invalid();
            String encoded=json.writeValueAsString(p);
            List<String> existing=db.query("SELECT payload FROM run.inputs WHERE session_id=? AND stream_seq=?",(rs,n)->rs.getString(1),id,p.seq());
            if(!existing.isEmpty()) {
                if(!json.readValue(existing.getFirst(),Input.class).equals(p)) throw new AppException(RunErrorCode.CONFLICT);
            } else {
                if(!List.of("PREPARED","NEEDS_DATA").contains(s.processing())) throw new AppException(RunErrorCode.CONFLICT);
                db.update("INSERT INTO run.inputs(session_id,stream_seq,payload) VALUES (?,?,?)",id,p.seq(),encoded);
            }
        }
        if(List.of("PREPARED","NEEDS_DATA").contains(s.processing())) {
            long count=db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,id);
            db.update("UPDATE run.sessions SET updated_at=now(),final_seq=?,processing=? WHERE id=?",request.finalSeq(),count==request.finalSeq()+1?"PROCESSING":"NEEDS_DATA",id);
        }
        return statusOf(session(owner,id,false));
    }
    @Transactional(readOnly=true)
    public Status status(UUID owner, UUID id) { return statusOf(session(owner,id,false)); }
    private Status statusOf(Session s) {
        List<Range> missing=new ArrayList<>();
        if("NEEDS_DATA".equals(s.processing())) {
            List<Long> seqs=db.query("SELECT stream_seq FROM run.inputs WHERE session_id=? ORDER BY stream_seq",(rs,n)->rs.getLong(1),s.id());
            long next=0;
            for(long seq:seqs) { if(seq>next) missing.add(new Range(next,seq-1)); next=seq+1; }
            if(next<=s.finalSeq()) missing.add(new Range(next,s.finalSeq()));
        }
        return new Status(s.id(),s.processing(),missing,"DONE".equals(s.processing())?s.id():null,s.failure());
    }
    public List<UUID> waiting() {
        return db.query("SELECT id FROM run.sessions WHERE processing='PROCESSING' ORDER BY started_at LIMIT 10",(rs,n)->rs.getObject(1,UUID.class));
    }
    @Transactional
    public void process(UUID id) {
        List<UUID> members=db.query("SELECT member_id FROM run.sessions WHERE id=?", (rs,n)->rs.getObject(1,UUID.class),id);
        if (members.isEmpty()) return;
        lockMember(members.getFirst());
        if (withdrawn(members.getFirst())) return;
        lock(id);
        if(db.queryForObject("SELECT count(*) FROM run.deleted_records WHERE id=?",Long.class,id)>0) return;
        List<Instant> starts=db.query("SELECT started_at FROM run.sessions WHERE id=? AND processing='PROCESSING' FOR UPDATE SKIP LOCKED",(rs,n)->rs.getTimestamp(1).toInstant(),id);
        if(starts.isEmpty()) return;
        List<Input> inputs=db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",(rs,n)->json.readValue(rs.getString(1),Input.class),id);
        FreeRunCalculator.Calculation calculation;
        try { calculation=FreeRunCalculator.calculate(starts.getFirst(),inputs); }
        catch(AppException e) { db.update("UPDATE run.sessions SET updated_at=now(),processing='FAILED',failure=? WHERE id=?",e.getErrorCode().getCode(),id); return; }
        if(calculation.metrics().distanceM()<=0) {
            db.update("UPDATE run.sessions SET updated_at=now(),processing='FAILED',failure='ZERO_DISTANCE' WHERE id=?",id); return;
        }
        Instant registered=clock.instant().truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        Result result=new Result(id,starts.getFirst(),calculation.endedAt(),registered,calculation.endReason(),calculation.metrics(),calculation.segments(),calculation.laps(),POLICY_VERSION,inputs.getFirst().reason(),calculation.stats());
        db.update("INSERT INTO run.records(id,registered_at,result_json,summary_json) VALUES (?,?,?,?)",id,Timestamp.from(registered),json.writeValueAsString(result),json.writeValueAsString(RecordSummary.from(result)));
        publishRegistration(members.getFirst(),result);
        db.update("UPDATE run.sessions SET updated_at=now(),processing='DONE' WHERE id=?",id);
    }
    @Transactional(readOnly=true)
    public Result result(UUID owner, UUID id) {
        session(owner,id,false);
        List<String> rows=db.query("SELECT result_json FROM run.records WHERE id=?",(rs,n)->rs.getString(1),id);
        if(rows.isEmpty()) throw new AppException(RunErrorCode.NOT_FOUND);
        Result stored = json.readValue(rows.getFirst(),Result.class);
        if (stored.stats() != null && RunResultStatsCalculator.VERSION.equals(stored.stats().version())) return stored;
        List<Input> inputs = db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",
            (rs,n)->json.readValue(rs.getString(1),Input.class),id);
        if (inputs.size() < 2) return stored;
        // Enrich old results on detail reads; keep stored distance/time/ranking intact.
        ResultStats stats = FreeRunCalculator.calculate(stored.startedAt(), inputs).stats();
        return new Result(stored.id(),stored.startedAt(),stored.endedAt(),stored.registeredAt(),stored.endReason(),
            stored.metrics(),stored.routeSegments(),stored.laps(),stored.policyVersion(),stored.calculationVersion(),stats);
    }
    @Transactional(readOnly=true)
    public CursorSlice<RecordSummary> history(UUID owner, Cursorable page) {
        Instant before=Instant.MAX;
        UUID beforeId=new UUID(-1L,-1L);
        if(page.cursor()!=null) {
            try { String[] parts=page.cursor().split("\\|",2); before=Instant.parse(parts[0]); beforeId=UUID.fromString(parts[1]); }
            catch(RuntimeException e) { invalid(); }
        }
        List<RecordSummary> rows;
        int limit=page.size()+1;
        if(page.cursor()==null) rows=db.query("SELECT r.summary_json FROM run.records r JOIN run.sessions s ON s.id=r.id WHERE s.member_id=? ORDER BY r.registered_at DESC,r.id DESC LIMIT ?",(rs,n)->json.readValue(rs.getString(1),RecordSummary.class),owner,limit);
        else rows=db.query("SELECT r.summary_json FROM run.records r JOIN run.sessions s ON s.id=r.id WHERE s.member_id=? AND (r.registered_at,r.id)<(?,?) ORDER BY r.registered_at DESC,r.id DESC LIMIT ?",(rs,n)->json.readValue(rs.getString(1),RecordSummary.class),owner,Timestamp.from(before),beforeId,limit);
        boolean more=rows.size()>page.size();
        List<RecordSummary> content=List.copyOf(rows.subList(0,Math.min(page.size(),rows.size())));
        RecordSummary last=content.isEmpty()?null:content.getLast();
        return new CursorSlice<>(content,more?last.registeredAt()+"|"+last.id():null);
    }
    public List<UUID> unpublished() {
        return db.query("SELECT id FROM run.records WHERE NOT registration_published ORDER BY registered_at LIMIT 10",(rs,n)->rs.getObject(1,UUID.class));
    }
    @Transactional
    public void publishStored(UUID id) {
        List<UUID> members=db.query("SELECT member_id FROM run.sessions WHERE id=?",(rs,n)->rs.getObject(1,UUID.class),id);
        if (members.isEmpty()) return;
        UUID member=members.getFirst(); lockMember(member); lock(id);
        if (withdrawn(member)) return;
        List<Result> results=db.query("SELECT result_json FROM run.records WHERE id=? AND NOT registration_published FOR UPDATE",(rs,n)->json.readValue(rs.getString(1),Result.class),id);
        if (!results.isEmpty()) publishRegistration(member,results.getFirst());
    }
    private void publishRegistration(UUID member, Result result) {
        events.publishEvent(new RunSessionEndedEvent(UuidV7.create(),result.registeredAt(),result.id(),member,null,false,
            result.metrics().distanceM(),0,0,0,0,false,null,result.startedAt(),result.endedAt(),result.registeredAt(),result.policyVersion()));
        db.update("UPDATE run.records SET registration_published=true,updated_at=now() WHERE id=?",result.id());
    }
    private static void invalid() { throw new AppException(RunErrorCode.INVALID); }
}
