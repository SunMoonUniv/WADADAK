package com.wadadak.run.internal;

import com.wadadak.common.exception.AppException;
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
    RunService(JdbcTemplate db, JsonMapper json) { this.db=db; this.json=json; }
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
        lock(id);
        List<UUID> owners = db.query("SELECT member_id FROM run.sessions WHERE id=? UNION SELECT member_id FROM run.deleted_records WHERE id=?", (rs,n)->rs.getObject(1,UUID.class),id,id);
        if (owners.stream().anyMatch(value -> !value.equals(owner))) throw new AppException(RunErrorCode.NOT_FOUND);
        db.update("INSERT INTO run.deleted_records(id,member_id) VALUES (?,?) ON CONFLICT DO NOTHING",id,owner);
        db.update("DELETE FROM run.records WHERE id=?",id);
        db.update("DELETE FROM run.inputs WHERE session_id=?",id);
        db.update("DELETE FROM run.sessions WHERE id=?",id);
        return new Deleted(id,true);
    }
    @Transactional
    public Status prepare(UUID owner, UUID id, Prepare request) {
        lock(id); ensureNotDeleted(id);
        if(request.startedAt()==null || !"FREE".equals(request.mode()) || request.startedAt().isAfter(Instant.now().plusSeconds(300))) invalid();
        db.update("INSERT INTO run.sessions(id,member_id,started_at,processing) VALUES (?,?,?,'PREPARED') ON CONFLICT DO NOTHING",
            id,owner,Timestamp.from(request.startedAt()));
        Session s=session(owner,id,true);
        if(!s.startedAt().equals(request.startedAt())) throw new AppException(RunErrorCode.CONFLICT);
        return statusOf(s);
    }
    @Transactional
    public Status upload(UUID owner, UUID id, Upload request) {
        lock(id); ensureNotDeleted(id);
        Session s=session(owner,id,true);
        if(s.finalSeq()!=null && s.finalSeq()!=request.finalSeq()) throw new AppException(RunErrorCode.CONFLICT);
        for(Input p:request.inputs()) {
            if(p.seq()>request.finalSeq() || p.elapsedMs()>7L*86400000 ||
                (p.kind()==Kind.GPS && (p.location()==null || p.accuracyM()==null)) ||
                (p.accuracyM()!=null && (!Double.isFinite(p.accuracyM()) || p.accuracyM()<0))) invalid();
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
            db.update("UPDATE run.sessions SET final_seq=?,processing=? WHERE id=?",request.finalSeq(),count==request.finalSeq()+1?"PROCESSING":"NEEDS_DATA",id);
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
        lock(id);
        if(db.queryForObject("SELECT count(*) FROM run.deleted_records WHERE id=?",Long.class,id)>0) return;
        List<Instant> starts=db.query("SELECT started_at FROM run.sessions WHERE id=? AND processing='PROCESSING' FOR UPDATE SKIP LOCKED",(rs,n)->rs.getTimestamp(1).toInstant(),id);
        if(starts.isEmpty()) return;
        List<Input> inputs=db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",(rs,n)->json.readValue(rs.getString(1),Input.class),id);
        FreeRunCalculator.Calculation calculation;
        try { calculation=FreeRunCalculator.calculate(starts.getFirst(),inputs); }
        catch(AppException e) { db.update("UPDATE run.sessions SET processing='FAILED',failure=? WHERE id=?",e.getErrorCode().getCode(),id); return; }
        if(calculation.metrics().distanceM()<=0) {
            db.update("UPDATE run.sessions SET processing='FAILED',failure='ZERO_DISTANCE' WHERE id=?",id); return;
        }
        Instant registered=Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        Result result=new Result(id,starts.getFirst(),calculation.endedAt(),registered,calculation.endReason(),calculation.metrics(),calculation.segments(),calculation.laps());
        db.update("INSERT INTO run.records(id,registered_at,result_json) VALUES (?,?,?)",id,Timestamp.from(registered),json.writeValueAsString(result));
        db.update("UPDATE run.sessions SET processing='DONE' WHERE id=?",id);
    }
    @Transactional(readOnly=true)
    public Result result(UUID owner, UUID id) {
        session(owner,id,false);
        List<String> rows=db.query("SELECT result_json FROM run.records WHERE id=?",(rs,n)->rs.getString(1),id);
        if(rows.isEmpty()) throw new AppException(RunErrorCode.NOT_FOUND);
        return json.readValue(rows.getFirst(),Result.class);
    }
    @Transactional(readOnly=true)
    public Page history(UUID owner, String cursor) {
        Instant before=Instant.MAX;
        UUID beforeId=new UUID(-1L,-1L);
        if(cursor!=null) {
            try { String[] parts=cursor.split("\\|",2); before=Instant.parse(parts[0]); beforeId=UUID.fromString(parts[1]); }
            catch(RuntimeException e) { invalid(); }
        }
        List<Result> rows;
        if(cursor==null) rows=db.query("SELECT r.result_json FROM run.records r JOIN run.sessions s ON s.id=r.id WHERE s.member_id=? ORDER BY r.registered_at DESC,r.id DESC LIMIT 21",(rs,n)->json.readValue(rs.getString(1),Result.class),owner);
        else rows=db.query("SELECT r.result_json FROM run.records r JOIN run.sessions s ON s.id=r.id WHERE s.member_id=? AND (r.registered_at,r.id)<(?,?) ORDER BY r.registered_at DESC,r.id DESC LIMIT 21",(rs,n)->json.readValue(rs.getString(1),Result.class),owner,Timestamp.from(before),beforeId);
        boolean more=rows.size()>20;
        List<Result> page=rows.subList(0,Math.min(20,rows.size()));
        Result last=page.isEmpty()?null:page.getLast();
        return new Page(page.stream().map(RecordSummary::from).toList(),more?last.registeredAt()+"|"+last.id():null);
    }
    private static void invalid() { throw new AppException(RunErrorCode.INVALID); }
}
