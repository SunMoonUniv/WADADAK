package com.wadadak.run.internal.recording;

import com.wadadak.common.exception.AppException;
import com.wadadak.common.entity.UuidV7;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.event.run.RunRecordDeletedEvent;
import org.springframework.context.ApplicationEventPublisher;
import java.time.Clock;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.RunErrorCode;
import com.wadadak.common.geo.GeoPoint;
import com.wadadak.course.GpsGapCheck;
import com.wadadak.run.internal.metrics.FreeRunCalculator;
import com.wadadak.run.internal.metrics.RunResultStatsCalculator;
import org.springframework.data.domain.PageRequest;
import java.util.Map;
import java.util.LinkedHashMap;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

@Service
class RunService {
    private final RunSessionRepository sessions;
    private final RunRecordRepository records;
    private final DeletedRunRecordRepository deletedRecords;
    private final WithdrawnRunMemberRepository withdrawnMembers;
    private final RunInputRepository inputs;
    private final RunLocks locks;
    private final JsonMapper json;
    private final ApplicationEventPublisher events;
    private final Clock clock;
    private final CourseRunService courseRuns;
    private final GhostResultService ghostResults;
    static final String POLICY_VERSION = "2026-10-14";
    RunService(RunSessionRepository sessions, RunRecordRepository records,
               DeletedRunRecordRepository deletedRecords, WithdrawnRunMemberRepository withdrawnMembers,
               RunInputRepository inputs, RunLocks locks, JsonMapper json,
               ApplicationEventPublisher events, Clock clock, CourseRunService courseRuns, GhostResultService ghostResults) {
        this.sessions=sessions; this.records=records; this.deletedRecords=deletedRecords;
        this.withdrawnMembers=withdrawnMembers; this.inputs=inputs; this.locks=locks;
        this.json=json; this.events=events; this.clock=clock; this.courseRuns=courseRuns;
        this.ghostResults=ghostResults;
    }
    private void ensureActiveMember(UUID member) {
        if (withdrawnMembers.existsById(member)) throw new AppException(RunErrorCode.NOT_FOUND);
    }
    @Transactional
    public void withdraw(UUID member, Instant withdrawnAt) {
        locks.member(member);
        if (!withdrawnMembers.existsById(member))
            withdrawnMembers.save(new WithdrawnRunMember(member,withdrawnAt));
        for (UUID id : sessions.findIdsByMemberId(member)) {
            locks.session(id);
            deleteStored(member,id);
        }
        courseRuns.forgetMember(member); // 업로드 전(세션 없음) 코스 시도
    }
    private RunSession session(UUID owner, UUID id, boolean lock) {
        return (lock ? sessions.findOwnedForUpdate(id,owner) : sessions.findByIdAndMemberId(id,owner))
            .orElseThrow(()->new AppException(RunErrorCode.NOT_FOUND));
    }
    private void ensureNotDeleted(UUID id) {
        if (deletedRecords.existsById(id)) throw new AppException(RunErrorCode.NOT_FOUND);
    }
    @Transactional
    public Deleted delete(UUID owner, UUID id) {
        locks.member(owner); ensureActiveMember(owner); locks.session(id);
        return deleteStored(owner,id);
    }
    private Deleted deleteStored(UUID owner, UUID id) {
        sessions.findMemberId(id).ifPresent(member -> requireOwner(owner,member));
        courseRuns.requireOwnerIfPresent(owner, id);
        var deleted=deletedRecords.findById(id);
        deleted.ifPresent(record -> requireOwner(owner,record.getMemberId()));
        records.findById(id).ifPresent(record -> {
            Result r=json.readValue(record.getResultJson(),Result.class);
            CourseOutcome c=r.course();
            // 코스 기록이면 도전 수를 더한 시작 이벤트 시각(같은 날짜에서 빼게)과 완주·코스 시간을 담는다
            events.publishEvent(new RunRecordDeletedEvent(UuidV7.create(),clock.instant(),id,owner,
                c==null?null:c.courseId(),c!=null&&c.completed(),r.metrics().distanceM(),
                c==null?0:Math.toIntExact(c.courseElapsedSeconds()),
                c==null?r.startedAt():courseRuns.startedEventAt(id).orElse(r.startedAt()),r.endedAt(),r.registeredAt()));
            records.delete(record);
        });
        if (deleted.isEmpty()) deletedRecords.save(new DeletedRunRecord(id,owner,clock.instant()));
        courseRuns.forget(id);
        // Flush JPA child deletions before JDBC removes inputs and JPA removes their parent.
        records.flush();
        inputs.delete(id);
        sessions.deleteById(id);
        sessions.flush();
        return new Deleted(id,true);
    }
    private static void requireOwner(UUID owner, UUID storedOwner) {
        if (!owner.equals(storedOwner)) throw new AppException(RunErrorCode.NOT_FOUND);
    }
    @Transactional
    public Status prepare(UUID owner, UUID id, Prepare request) {
        locks.member(owner); ensureActiveMember(owner); locks.session(id); ensureNotDeleted(id);
        if(request.startedAt()==null || request.startedAt().isAfter(clock.instant().plusSeconds(300))) invalid();
        courseRuns.checkPrepare(owner,id,request.mode(),request.startedAt()); // COURSE는 시작 신호를 보낸 세션만
        // The advisory ID lock protects first creation and retries, including different owners.
        RunSession s=sessions.findById(id).orElseGet(()->sessions.save(new RunSession(id,owner,request.startedAt())));
        requireOwner(owner,s.getMemberId());
        if(!s.getStartedAt().equals(request.startedAt())) throw new AppException(RunErrorCode.CONFLICT);
        return statusOf(s);
    }
    @Transactional
    public Status upload(UUID owner, UUID id, Upload request) {
        locks.member(owner); ensureActiveMember(owner); locks.session(id); ensureNotDeleted(id);
        RunSession s=session(owner,id,true);
        if(s.getFinalSeq()!=null && s.getFinalSeq()!=request.finalSeq()) throw new AppException(RunErrorCode.CONFLICT);
        Map<Long,Input> existing=inputs.findExisting(id,request.inputs().stream().map(Input::seq).toList());
        Map<Long,Input> pending=new LinkedHashMap<>();
        for(Input p:request.inputs()) {
            validate(p,request.finalSeq());
            Input previous=existing.get(p.seq());
            if(previous==null) previous=pending.get(p.seq());
            if(previous!=null) {
                if(!previous.equals(p)) throw new AppException(RunErrorCode.CONFLICT);
            } else {
                if(!s.acceptsInputs()) throw new AppException(RunErrorCode.CONFLICT);
                pending.put(p.seq(),p);
            }
        }
        // JpaTransactionManager shares the DataSource/connection with JdbcTemplate.
        // Flush newly persisted sessions before JDBC inserts their child stream rows.
        sessions.flush();
        inputs.insertBatch(id,pending.values());
        if(s.acceptsInputs()) s.accept(request.finalSeq(),inputs.count(id));
        // 기록이 다 도착하면 현재 러너 수에서 뺀다(구간 종료 신호가 없었던 경우, 공통 7)
        if("PROCESSING".equals(s.getProcessing())) courseRuns.releaseOnUpload(id);
        return statusOf(s);
    }
    private static void validate(Input p,long finalSeq) {
            if(p.seq()>finalSeq || p.elapsedMs()>7L*86400000 ||
                (p.kind()==Kind.GPS && (p.location()==null || p.accuracyM()==null)) ||
                (p.accuracyM()!=null && (!Double.isFinite(p.accuracyM()) || p.accuracyM()<0)) ||
                (p.altitudeM()!=null && (!Double.isFinite(p.altitudeM()) || p.kind()!=Kind.GPS)) ||
                (p.pressureHpa()!=null && (p.kind()!=Kind.BAROMETER || !Double.isFinite(p.pressureHpa()) || p.pressureHpa()<=0)) ||
                (p.pressureAccuracy()!=null && (p.kind()!=Kind.BAROMETER || p.pressureAccuracy()<0 || p.pressureAccuracy()>3)) ||
                (p.kind()==Kind.BAROMETER && (p.pressureHpa()==null || p.pressureAccuracy()==null || p.sampleEndMs()==null || p.sampleEndMs()<0 || p.sampleEndMs()>p.elapsedMs() || p.elapsedMs()-p.sampleEndMs()>2000)) ||
                (p.altitudeAccuracyM()!=null && (!Double.isFinite(p.altitudeAccuracyM()) || p.altitudeAccuracyM()<0 || p.altitudeM()==null))) invalid();
    }
    @Transactional(readOnly=true)
    public Status status(UUID owner, UUID id) { return statusOf(session(owner,id,false)); }
    private Status statusOf(RunSession s) {
        List<Range> missing=new ArrayList<>();
        if("NEEDS_DATA".equals(s.getProcessing())) {
            List<Long> seqs=inputs.sequences(s.getId());
            long next=0;
            for(long seq:seqs) { if(seq>next) missing.add(new Range(next,seq-1)); next=seq+1; }
            if(next<=s.getFinalSeq()) missing.add(new Range(next,s.getFinalSeq()));
        }
        return new Status(s.getId(),s.getProcessing(),missing,"DONE".equals(s.getProcessing())?s.getId():null,s.getFailure());
    }
    @Transactional(readOnly=true)
    public List<UUID> waiting() {
        return sessions.findWaitingIds(PageRequest.of(0,10));
    }
    @Transactional
    public void process(UUID id) {
        var member=sessions.findMemberId(id);
        if(member.isEmpty()) return;
        locks.member(member.get());
        if(withdrawnMembers.existsById(member.get())) return;
        locks.session(id);
        if(deletedRecords.existsById(id)) return;
        var pending=sessions.findProcessingForUpdate(id);
        if(pending.isEmpty()) return;
        RunSession session=pending.get();
        List<Input> raw=inputs.findAll(id);
        FreeRunCalculator.Calculation calculation;
        try { calculation=FreeRunCalculator.calculate(session.getStartedAt(),raw); }
        catch(AppException e) { session.fail(e.getErrorCode().getCode()); return; }
        Instant registered=clock.instant().truncatedTo(java.time.temporal.ChronoUnit.MICROS);
        // 코스 러닝이면 시작 때 저장한 코스 스냅샷으로 서버가 완주·인정 거리·리뷰 자격을 판정한다(정책 5.3)
        CourseOutcome course=courseRuns.judge(id,raw);
        GhostOutcome ghost=ghostResults.finalizeResult(id,course,raw,registered);
        if(calculation.metrics().distanceM()<=0) {
            session.fail("ZERO_DISTANCE"); return;
        }
        Result result=new Result(id,session.getStartedAt(),calculation.endedAt(),registered,calculation.endReason(),calculation.metrics(),calculation.segments(),calculation.laps(),POLICY_VERSION,raw.getFirst().reason(),calculation.stats(),course,null,ghost);
        var summary=RecordSummary.from(result,RunRouteThumbnail.create(calculation.segments()));
        RunRecord record=records.save(new RunRecord(id,registered,json.writeValueAsString(result),json.writeValueAsString(summary)));
        publishRegistration(member.get(),record,result);
        session.complete();
    }
    @Transactional(readOnly=true)
    public Result result(UUID owner, UUID id) {
        session(owner,id,false);
        RunRecord record=records.findById(id).orElseThrow(()->new AppException(RunErrorCode.NOT_FOUND));
        Result stored=json.readValue(record.getResultJson(),Result.class);
        if (stored.stats()!=null && RunResultStatsCalculator.VERSION.equals(stored.stats().version())) return stored;
        List<Input> raw=inputs.findAll(id);
        if(raw.size()<2) return stored;
        // Enrich old results on detail reads; keep stored distance/time/ranking intact.
        ResultStats stats = FreeRunCalculator.calculate(stored.startedAt(), raw).stats();
        return new Result(stored.id(),stored.startedAt(),stored.endedAt(),stored.registeredAt(),stored.endReason(),
            stored.metrics(),stored.routeSegments(),stored.laps(),stored.policyVersion(),stored.calculationVersion(),stats,stored.course(),stored.gpsGap(),stored.ghost());
    }
    /** 끊긴 구간 판단이 없거나 [version]과 다른 기록(판단 도입 전·기준 변경) */
    @Transactional(readOnly=true)
    public List<UUID> gpsGapOutdated(String version) {
        return records.findGpsGapOutdated(version,50);
    }
    /**
     * 끊긴 구간 판단에 넣을 경로 조각(course-source와 같은 점). 기록이 없으면 null.
     * 원본이 지금 계산 규칙으로 계산되지 않으면 빈 조각(판단은 GPS 정확도 부족)
     */
    @Transactional(readOnly=true)
    public List<List<GeoPoint>> gpsGapSegments(UUID id) {
        RunRecord record=records.findById(id).orElse(null);
        if(record==null) return null;
        Result stored=json.readValue(record.getResultJson(),Result.class);
        try { return FreeRunCalculator.calculate(stored.startedAt(),inputs.findAll(id)).segments(); }
        catch(AppException e) { return List.of(); }
    }
    /** 끊긴 구간 판단을 결과·목록에 넣는다. 판단(CourseApi)은 이 트랜잭션 밖에서 한다(개발 정책 4.4) */
    @Transactional
    public void saveGpsGap(UUID id, GpsGapCheck check) {
        RunRecord record=records.findById(id).orElse(null);
        if(record==null) return;
        Result updated=json.readValue(record.getResultJson(),Result.class).withGpsGap(check);
        // 목록 전용 파생 값은 결과 JSON에 없으므로, 저장된 요약에서 판단만 갱신한다.
        RecordSummary summary=json.readValue(record.getSummaryJson(),RecordSummary.class).withGpsGap(check);
        record.replaceJson(json.writeValueAsString(updated),json.writeValueAsString(summary));
    }
    /** GPS 코스 등록용 원본 경로. 결과 화면 지도와 같은 구간을 원본 입력에서 다시 만들어 지점별 정확도·고도를 붙인다 */
    @Transactional(readOnly=true)
    public CourseSource courseSource(UUID owner, UUID id) {
        session(owner,id,false);
        RunRecord record=records.findById(id).orElseThrow(()->new AppException(RunErrorCode.NOT_FOUND));
        Result stored=json.readValue(record.getResultJson(),Result.class);
        List<List<SourcePoint>> segments=FreeRunCalculator.calculate(stored.startedAt(),inputs.findAll(id)).samples().stream()
            .map(segment->segment.stream().map(p->new SourcePoint(p.location().lat(),p.location().lng(),p.accuracyM(),p.altitudeM(),p.altitudeAccuracyM())).toList())
            .toList();
        return new CourseSource(id,stored.metrics().distanceM(),segments);
    }
    @Transactional(readOnly=true)
    public CursorSlice<RecordSummary> history(UUID owner, Cursorable page) {
        Instant before=Instant.MAX;
        UUID beforeId=new UUID(-1L,-1L);
        if(page.cursor()!=null) {
            try { String[] parts=page.cursor().split("\\|",2); before=Instant.parse(parts[0]); beforeId=UUID.fromString(parts[1]); }
            catch(RuntimeException e) { invalid(); }
        }
        int limit=page.size()+1;
        List<String> summaries=page.cursor()==null ? records.findSummaries(owner,limit)
            : records.findSummariesBefore(owner,before,beforeId,limit);
        List<RecordSummary> rows=summaries.stream().map(value->json.readValue(value,RecordSummary.class)).toList();
        boolean more=rows.size()>page.size();
        List<RecordSummary> content=List.copyOf(rows.subList(0,Math.min(page.size(),rows.size())));
        RecordSummary last=content.isEmpty()?null:content.getLast();
        return new CursorSlice<>(content,more?last.registeredAt()+"|"+last.id():null);
    }
    @Transactional(readOnly=true)
    public List<UUID> unpublished() {
        return records.findUnpublishedIds(PageRequest.of(0,10));
    }
    @Transactional
    public void publishStored(UUID id) {
        var member=sessions.findMemberId(id);
        if(member.isEmpty()) return;
        locks.member(member.get()); locks.session(id);
        if(withdrawnMembers.existsById(member.get())) return;
        records.findUnpublishedForUpdate(id).ifPresent(record ->
            publishRegistration(member.get(),record,json.readValue(record.getResultJson(),Result.class)));
    }
    private void publishRegistration(UUID member,RunRecord record,Result result) {
        CourseOutcome c=result.course(); // 자유 러닝이면 null → 코스 칸은 비운다
        events.publishEvent(new RunSessionEndedEvent(UuidV7.create(),result.registeredAt(),result.id(),member,
            c==null?null:c.courseId(),c!=null&&c.completed(),result.metrics().distanceM(),
            c==null?0:Math.toIntExact(c.courseElapsedSeconds()),c==null?0:c.courseDistanceMeters(),
            c==null?0:c.recognizedDistanceMeters(),c==null?0:c.progressPercent(),c!=null&&c.reviewEligible(),
            c==null?null:c.completedAt(),result.startedAt(),result.endedAt(),result.registeredAt(),result.policyVersion()));
        record.markRegistrationPublished();
    }
    private static void invalid() { throw new AppException(RunErrorCode.INVALID); }
}
