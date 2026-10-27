package com.wadadak.run.internal.recording;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.run.internal.RunContracts.*;
import com.wadadak.run.internal.metrics.FreeRunCalculator;
import com.wadadak.common.paging.CursorSlice;
import com.wadadak.common.paging.Cursorable;
import com.wadadak.event.member.MemberWithdrawnEvent;
import com.wadadak.event.run.RunSessionEndedEvent;
import com.wadadak.event.run.RunRecordDeletedEvent;
import org.springframework.modulith.test.AssertablePublishedEvents;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.transaction.support.TransactionTemplate;
import java.time.Duration;
import static org.awaitility.Awaitility.await;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@ApplicationModuleTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RunIngestionTest {
    @org.springframework.test.context.bean.override.mockito.MockitoBean com.wadadak.ranking.RankingApi rankingApi;
    @Autowired RunService runs;
    @Autowired JdbcTemplate db;
    @Autowired JsonMapper json;
    @Autowired MockMvc mvc;
    @Autowired ApplicationEventPublisher events;
    @Autowired TransactionTemplate tx;
    @Autowired RunSessionRepository sessions;
    @Autowired RunRecordRepository records;
    @MockitoBean RunProcessingWorker worker;
    // run 모듈만 띄우므로 course 모듈의 CourseApi는 없다. 자유 러닝 테스트는 코스를 부르지 않는다
    @MockitoBean com.wadadak.course.CourseApi courseApi;
    @MockitoBean CourseRunReleaseWorker courseRunReleaseWorker;
    @MockitoBean GpsGapWorker gpsGapWorker;
    final UUID owner=UUID.randomUUID(),id=UUID.randomUUID();
    final Instant start=Instant.parse("2026-10-12T00:00:00Z");
    List<Input> inputs;
    @BeforeEach void prepare() throws Exception {
        db.update("DELETE FROM run.withdrawn_members"); db.update("DELETE FROM run.deleted_records"); db.update("DELETE FROM run.records"); db.update("DELETE FROM run.inputs"); db.update("DELETE FROM run.sessions");
        var fixture=json.readTree(Files.readString(Path.of("../run/fixtures/free_pause_v1.json")));
        inputs=new ArrayList<>();
        for(var node:fixture.get("inputs")) inputs.add(json.treeToValue(node,Input.class));
        runs.prepare(owner,id,new Prepare(start,"FREE"));
    }
    @Test void partialUploadIsDurableThenRegistersExactlyOnce() {
        var first=runs.upload(owner,id,new Upload(9,inputs.subList(0,5)));
        assertThat(first.processing()).isEqualTo("NEEDS_DATA");
        assertThat(first.missingRanges()).containsExactly(new Range(5,9));
        assertThat(runs.waiting()).isEmpty();
        runs.upload(owner,id,new Upload(9,inputs.subList(5,10)));
        assertThat(runs.waiting()).containsExactly(id);
        runs.process(id);
        Result record=runs.result(owner,id);
        assertThat(record.metrics().distanceM()).isCloseTo(22.239016,within(0.000001));
        assertThat(record.metrics().activeMs()).isEqualTo(100000);
        assertThat(runs.upload(owner,id,new Upload(9,inputs)).processing()).isEqualTo("DONE");
        runs.prepare(owner,id,new Prepare(start,"FREE")); runs.process(id);
        assertThat(runs.result(owner,id).registeredAt()).isEqualTo(record.registeredAt());
        assertThat(db.queryForObject("SELECT count(*) FROM run.records",Long.class)).isEqualTo(1);
    }
    @Test void resultStatsSurviveUploadStorageHistoryAndLegacyDetailEnrichment() throws Exception {
        var fixture=json.readTree(Files.readString(Path.of("../run/fixtures/free_result_stats_v2.json")));
        var source=fixture.get("cases").get(0);
        var raw=new ArrayList<Input>();
        for(var node:source.get("inputs")) {
            Input p=json.treeToValue(node,Input.class);
            raw.add(new Input(p.seq(),p.kind(),p.elapsedMs(),start.plusMillis(p.elapsedMs()),p.location(),p.accuracyM(),
                p.reason(),p.speedMps(),p.speedAccuracyMps(),p.steps(),p.durationMs(),p.sampleEndMs(),p.altitudeM(),p.altitudeAccuracyM()));
        }
        for(int from=0;from<raw.size();from+=400)
            runs.upload(owner,id,new Upload(raw.size()-1,raw.subList(from,Math.min(from+400,raw.size()))));
        runs.process(id);
        Result stored=runs.result(owner,id);
        assertThat(stored.stats().elevationGainM()).isCloseTo(40,within(.000001));
        assertThat(stored.stats().bestLapNumber()).isEqualTo(2);
        assertThat(stored.stats().bestPaceSecondsPerKm()).isCloseTo(200,within(.000001));
        assertThat(runs.history(owner,new Cursorable(null,null)).content().getFirst().stats()).isEqualTo(stored.stats());
        mvc.perform(get("/api/v1/runs/records/"+id).with(jwt().jwt(j->j.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.stats.version").value("RESULT_V3"));

        // Simulate a record saved before stats existed. Only enrich the read:
        // registered time, original metrics, laps and ranking publication survive.
        var legacy=json.readTree(json.writeValueAsString(stored)).deepCopy();
        ((tools.jackson.databind.node.ObjectNode)legacy).remove("stats");
        db.update("UPDATE run.records SET result_json=? WHERE id=?",json.writeValueAsString(legacy),id);
        Result enriched=runs.result(owner,id);
        assertThat(enriched.stats()).isEqualTo(stored.stats());
        assertThat(enriched.metrics()).isEqualTo(stored.metrics());
        assertThat(enriched.laps()).isEqualTo(stored.laps());
        assertThat(enriched.registeredAt()).isEqualTo(stored.registeredAt());
        var oldStats = new ResultStats("RESULT_V1",0.0,false,stored.stats().bestLapNumber(),
            stored.stats().bestLapPaceSecondsPerKm(),stored.stats().bestPaceSecondsPerKm());
        var v1 = new Result(stored.id(),stored.startedAt(),stored.endedAt(),stored.registeredAt(),stored.endReason(),
            stored.metrics(),stored.routeSegments(),stored.laps(),stored.policyVersion(),stored.calculationVersion(),oldStats);
        db.update("UPDATE run.records SET result_json=? WHERE id=?",json.writeValueAsString(v1),id);
        assertThat(runs.result(owner,id).stats()).isEqualTo(stored.stats());
        assertThat(json.readValue(db.queryForObject("SELECT result_json FROM run.records WHERE id=?",String.class,id),Result.class).stats()).isEqualTo(oldStats);
        assertThat(db.queryForObject("SELECT registration_published FROM run.records WHERE id=?",Boolean.class,id)).isTrue();
        assertThatThrownBy(()->runs.result(UUID.randomUUID(),id)).isInstanceOf(AppException.class);
    }
    @Test void conflictingBatchRollsBackAndAnotherOwnerCannotAccess() {
        runs.upload(owner,id,new Upload(9,List.of(inputs.getFirst())));
        var changed=new Input(0,Kind.START,100,start.plusMillis(100),null,null,null);
        assertThatThrownBy(()->runs.upload(owner,id,new Upload(9,List.of(inputs.get(1),changed)))).isInstanceOf(AppException.class);
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs",Long.class)).isEqualTo(1);
        assertThatThrownBy(()->runs.status(UUID.randomUUID(),id)).isInstanceOf(AppException.class);
        assertThatThrownBy(()->runs.prepare(UUID.randomUUID(),id,new Prepare(start,"FREE"))).isInstanceOf(AppException.class);
    }
    @Test void duplicatesWithinOneBatchAreIdempotentAndConflictingPayloadsAreRejected() {
        Input changed=new Input(0,Kind.START,100,start.plusMillis(100),null,null,null);
        assertThatThrownBy(()->runs.upload(owner,id,new Upload(9,List.of(inputs.get(1),inputs.getFirst(),changed))))
            .isInstanceOf(AppException.class);
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,id)).isZero();
        assertThat(runs.status(owner,id).processing()).isEqualTo("PREPARED");
        assertThat(runs.upload(owner,id,new Upload(9,List.of(inputs.getFirst(),inputs.getFirst(),inputs.get(1)))).processing())
            .isEqualTo("NEEDS_DATA");
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,id)).isEqualTo(2);
        runs.upload(owner,id,new Upload(9,inputs));
        runs.process(id);
        assertThat(runs.status(owner,id).processing()).isEqualTo("DONE");
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,id)).isEqualTo(10);
    }
    @Test void jpaStateAndJdbcInputsCommitAndRollBackInTheSameTransaction() {
        UUID newId=UUID.randomUUID();
        assertThatThrownBy(()->tx.executeWithoutResult(status->{
            runs.prepare(owner,newId,new Prepare(start,"FREE"));
            runs.upload(owner,newId,new Upload(9,inputs));
            runs.process(newId);
            records.flush();
            assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,newId)).isEqualTo(10);
            assertThat(db.queryForObject("SELECT processing FROM run.sessions WHERE id=?",String.class,newId)).isEqualTo("DONE");
            assertThat(db.queryForObject("SELECT count(*) FROM run.records WHERE id=?",Long.class,newId)).isOne();
            throw new IllegalStateException("rollback JPA and JDBC together");
        })).isInstanceOf(IllegalStateException.class).hasMessage("rollback JPA and JDBC together");
        assertThat(sessions.existsById(newId)).isFalse();
        assertThat(records.existsById(newId)).isFalse();
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,newId)).isZero();

        tx.executeWithoutResult(status->{
            runs.prepare(owner,newId,new Prepare(start,"FREE"));
            runs.upload(owner,newId,new Upload(9,inputs));
            runs.process(newId);
        });
        assertThat(runs.status(owner,newId).processing()).isEqualTo("DONE");
        assertThat(runs.result(owner,newId).metrics().distanceM()).isPositive();
        assertThat(sessions.findById(newId).orElseThrow().getCreatedAt()).isNotNull();
        assertThat(records.findById(newId).orElseThrow().getUpdatedAt()).isNotNull();
    }
    @Test void simultaneousFirstPreparationCreatesOneSessionAndKeepsOriginalStart() {
        UUID newId=UUID.randomUUID();
        try(var executor=Executors.newFixedThreadPool(2)) {
            var first=CompletableFuture.supplyAsync(()->runs.prepare(owner,newId,new Prepare(start,"FREE")),executor);
            var second=CompletableFuture.supplyAsync(()->runs.prepare(owner,newId,new Prepare(start,"FREE")),executor);
            assertThat(first.join().processing()).isEqualTo("PREPARED");
            assertThat(second.join().processing()).isEqualTo("PREPARED");
        }
        assertThat(db.queryForObject("SELECT count(*) FROM run.sessions WHERE id=?",Long.class,newId)).isOne();
        assertThatThrownBy(()->runs.prepare(owner,newId,new Prepare(start.plusSeconds(1),"FREE")))
            .isInstanceOf(AppException.class);
        assertThat(sessions.findById(newId).orElseThrow().getStartedAt()).isEqualTo(start);
    }
    @Test void simultaneousRetriesAndWorkersRegisterOneRecord() {
        try (var executor = Executors.newFixedThreadPool(2)) {
            var first = CompletableFuture.supplyAsync(() -> runs.upload(owner,id,new Upload(9,inputs)),executor);
            var second = CompletableFuture.supplyAsync(() -> runs.upload(owner,id,new Upload(9,inputs)),executor);
            assertThat(first.join().processing()).isEqualTo("PROCESSING");
            assertThat(second.join().processing()).isEqualTo("PROCESSING");
            CompletableFuture.allOf(
                CompletableFuture.runAsync(() -> runs.process(id),executor),
                CompletableFuture.runAsync(() -> runs.process(id),executor)
            ).join();
        }
        assertThat(runs.status(owner,id).processing()).isEqualTo("DONE");
        assertThat(db.queryForObject("SELECT count(*) FROM run.records",Long.class)).isEqualTo(1);
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs",Long.class)).isEqualTo(10);
    }
    @Test void historyPagesHaveNoDuplicatesOrRoutesAndKeepOwnerBoundary() {
        for (int index=0; index<21; index++) {
            UUID recordId = index==0 ? id : UUID.randomUUID();
            runs.prepare(owner,recordId,new Prepare(start,"FREE"));
            runs.upload(owner,recordId,new Upload(9,inputs));
            runs.process(recordId);
        }
        CursorSlice<RecordSummary> first = runs.history(owner,new Cursorable(null,null));
        CursorSlice<RecordSummary> second = runs.history(owner,new Cursorable(first.nextCursor(),null));
        assertThat(first.content()).hasSize(20);
        assertThat(second.content()).hasSize(1);
        assertThat(second.nextCursor()).isNull();
        List<UUID> all = new ArrayList<>();
        first.content().forEach(record -> all.add(record.id()));
        second.content().forEach(record -> all.add(record.id()));
        assertThat(all).doesNotHaveDuplicates();
        assertThat(json.writeValueAsString(first)).doesNotContain("routeSegments");
        assertThat(runs.result(owner,all.getFirst()).routeSegments()).isNotEmpty();
        assertThat(runs.history(UUID.randomUUID(),new Cursorable(null,null)).content()).isEmpty();
        assertThatThrownBy(() -> runs.history(owner,new Cursorable("invalid-cursor",null))).isInstanceOf(AppException.class);
    }
    @Test void zeroDistanceAndImpossibleStateNeverBecomePersonalRecords() {
        var pause=new Input(1,Kind.PAUSE,1000,start.plusMillis(1000),null,null,null);
        var end=new Input(2,Kind.END,1000,start.plusMillis(1000),null,null,"USER");
        runs.upload(owner,id,new Upload(2,List.of(inputs.getFirst(),pause,end))); runs.process(id);
        assertThat(runs.status(owner,id).failure()).isEqualTo("ZERO_DISTANCE");
        assertThat(runs.history(owner,new Cursorable(null,null)).content()).isEmpty();
    }
    @Test void endpointsRequireAuthenticationAndValidateNullInputs() throws Exception {
        mvc.perform(get("/api/v1/runs/records")).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/v1/runs/sessions/"+id+"/record")
            .with(jwt().jwt(j->j.subject(owner.toString())))
            .contentType("application/json").content("{\"finalSeq\":1,\"inputs\":[null]}"))
            .andExpect(status().isBadRequest());
        mvc.perform(get("/api/v1/runs/sessions/"+id+"/status")
            .with(jwt().jwt(j->j.subject(UUID.randomUUID().toString()))))
            .andExpect(status().isNotFound());
    }
    @Test void deletionIsOwnerScopedIdempotentAndRejectsDelayedUpload() {
        runs.upload(owner,id,new Upload(9,inputs)); runs.process(id);
        assertThatThrownBy(()->runs.delete(UUID.randomUUID(),id)).isInstanceOf(AppException.class);
        assertThat(runs.delete(owner,id).deleted()).isTrue();
        assertThat(runs.delete(owner,id).deleted()).isTrue();
        assertThat(runs.history(owner,new Cursorable(null,null)).content()).isEmpty();
        assertThatThrownBy(()->runs.result(owner,id)).isInstanceOf(AppException.class);
        assertThatThrownBy(()->runs.prepare(owner,id,new Prepare(start,"FREE"))).isInstanceOf(AppException.class);
        assertThatThrownBy(()->runs.upload(owner,id,new Upload(9,inputs))).isInstanceOf(AppException.class);
        runs.process(id);
        assertThat(db.queryForObject("SELECT count(*) FROM run.records WHERE id=?",Long.class,id)).isZero();
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,id)).isZero();
    }
    @Test void deletingBeforeFirstUploadReservesIdAndProcessingRaceCannotRestoreIt() {
        UUID unsent=UUID.randomUUID();
        runs.delete(owner,unsent);
        assertThatThrownBy(()->runs.prepare(owner,unsent,new Prepare(start,"FREE"))).isInstanceOf(AppException.class);
        assertThatThrownBy(()->runs.delete(UUID.randomUUID(),unsent)).isInstanceOf(AppException.class);
        runs.upload(owner,id,new Upload(9,inputs));
        try(var executor=Executors.newFixedThreadPool(2)) {
            CompletableFuture.allOf(CompletableFuture.runAsync(()->runs.process(id),executor),
                CompletableFuture.runAsync(()->runs.delete(owner,id),executor)).join();
        }
        assertThat(runs.history(owner,new Cursorable(null,null)).content()).isEmpty();
        assertThat(db.queryForObject("SELECT count(*) FROM run.records WHERE id=?",Long.class,id)).isZero();
    }
    @Test void deleteEndpointConfirmsReservationAndHidesRecordFromOtherOwners() throws Exception {
        mvc.perform(delete("/api/v1/runs/records/"+id).with(jwt().jwt(t->t.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.deleted").value(true));
        mvc.perform(delete("/api/v1/runs/records/"+id).with(jwt().jwt(t->t.subject(UUID.randomUUID().toString()))))
            .andExpect(status().isNotFound());
    }

    @Test void publishesOneRegistrationAndOneDeletionWithOriginalValues(AssertablePublishedEvents events) {
        runs.upload(owner,id,new Upload(9,inputs)); runs.process(id);
        Result r=runs.result(owner,id);
        runs.process(id); runs.prepare(owner,id,new Prepare(start,"FREE"));
        assertThat(events.ofType(RunSessionEndedEvent.class)).hasSize(1);
        RunSessionEndedEvent registered=events.ofType(RunSessionEndedEvent.class).iterator().next();
        assertThat(registered.courseId()).isNull();
        assertThat(registered.completed()).isFalse();
        assertThat(registered.distanceMeters()).isEqualTo(r.metrics().distanceM());
        assertThat(registered.registeredAt()).isEqualTo(r.registeredAt());
        assertThat(registered.policyVersion()).isEqualTo("2026-10-14");
        assertThat(registered.eventId().version()).isEqualTo(7);
        runs.delete(owner,id); runs.delete(owner,id);
        assertThat(events.ofType(RunRecordDeletedEvent.class)).hasSize(1);
        RunRecordDeletedEvent deleted=events.ofType(RunRecordDeletedEvent.class).iterator().next();
        assertThat(deleted.distanceMeters()).isEqualTo(r.metrics().distanceM());
        assertThat(deleted.registeredAt()).isEqualTo(r.registeredAt());
    }
    @Test void withdrawalEventDeletesAllRawDataAndBlocksFutureUpload() {
        runs.upload(owner,id,new Upload(9,inputs)); runs.process(id);
        UUID pending=UUID.randomUUID();
        runs.prepare(owner,pending,new Prepare(start,"FREE"));
        MemberWithdrawnEvent event=new MemberWithdrawnEvent(UUID.randomUUID(),Instant.now(),owner,Instant.now());
        tx.executeWithoutResult(status->events.publishEvent(event));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(()->
            assertThat(db.queryForObject("SELECT count(*) FROM run.sessions WHERE member_id=?",Long.class,owner)).isZero());
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs",Long.class)).isZero();
        assertThat(db.queryForObject("SELECT count(*) FROM run.records",Long.class)).isZero();
        assertThatThrownBy(()->runs.prepare(owner,UUID.randomUUID(),new Prepare(start,"FREE"))).isInstanceOf(AppException.class);
        assertThatThrownBy(()->runs.upload(owner,id,new Upload(9,inputs))).isInstanceOf(AppException.class);
        tx.executeWithoutResult(status->events.publishEvent(event));
        await().atMost(Duration.ofSeconds(10)).untilAsserted(()->
            assertThat(db.queryForObject("SELECT count(*) FROM common.event_publication",Long.class)).isZero());
        assertThat(db.queryForObject("SELECT count(*) FROM run.withdrawn_members WHERE member_id=?",Long.class,owner)).isOne();
    }
    @Test void pendingPublicationPreservesOriginalRegistrationTime() {
        runs.upload(owner,id,new Upload(9,inputs)); runs.process(id);
        Instant original=runs.result(owner,id).registeredAt();
        db.update("UPDATE run.records SET registration_published=false WHERE id=?",id);
        assertThat(runs.unpublished()).contains(id);
        runs.publishStored(id); runs.publishStored(id);
        assertThat(runs.unpublished()).doesNotContain(id);
        assertThat(runs.result(owner,id).registeredAt()).isEqualTo(original);
    }
    @Test void listDoesNotReadRouteJsonAndUsesCommonPageSizeContract() throws Exception {
        runs.upload(owner,id,new Upload(9,inputs)); runs.process(id);
        db.update("UPDATE run.records SET result_json='not route json' WHERE id=?",id);
        assertThat(runs.history(owner,new Cursorable(null,1)).content()).hasSize(1);
        mvc.perform(get("/api/v1/runs/records?size=1").with(jwt().jwt(t->t.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.content[0].id").value(id.toString()))
            .andExpect(jsonPath("$.data.items").doesNotExist())
            .andExpect(jsonPath("$.data.content[0].routeSegments").doesNotExist());
        mvc.perform(get("/api/v1/runs/records?size=51").with(jwt().jwt(t->t.subject(owner.toString()))))
            .andExpect(status().isBadRequest());
    }

    @Test void altitudeFixturePersistsRawAndRetriesWithoutChangingRegistrationOrMetrics() throws Exception {
        var fixture=json.readTree(Files.readString(Path.of("../run/fixtures/free_altitude_v1.json")));
        List<Input> elevated=new ArrayList<>();
        for(var node:fixture.get("inputs")) elevated.add(json.treeToValue(node,Input.class));
        var expected=FreeRunCalculator.calculate(start,inputs);
        runs.upload(owner,id,new Upload(9,elevated));
        List<Input> stored=db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",
            (rs,n)->json.readValue(rs.getString(1),Input.class),id);
        assertThat(stored).containsExactlyElementsOf(elevated);
        assertThat(stored.get(1).altitudeM()).isZero();
        assertThat(stored.get(1).altitudeAccuracyM()).isZero();
        assertThat(stored.get(2).altitudeM()).isEqualTo(-3.25);
        assertThat(stored.get(6).altitudeAccuracyM()).isNull();
        assertThat(stored.get(7).altitudeM()).isNull();
        runs.process(id);
        Result first=runs.result(owner,id);
        assertThat(first.metrics()).isEqualTo(expected.metrics());
        assertThat(first.laps()).isEqualTo(expected.laps());
        runs.upload(owner,id,new Upload(9,elevated)); runs.process(id);
        assertThat(runs.result(owner,id)).isEqualTo(first);
        Input p=elevated.get(2);
        var changed=new Input(p.seq(),p.kind(),p.elapsedMs(),p.measuredAt(),p.location(),p.accuracyM(),
            p.reason(),p.speedMps(),p.speedAccuracyMps(),p.steps(),p.durationMs(),p.sampleEndMs(),99.0,p.altitudeAccuracyM());
        assertThatThrownBy(()->runs.upload(owner,id,new Upload(9,List.of(changed)))).isInstanceOf(AppException.class);
        assertThat(db.queryForObject("SELECT count(*) FROM run.records WHERE id=?",Long.class,id)).isEqualTo(1);
        assertThat(runs.result(owner,id).registeredAt()).isEqualTo(first.registeredAt());
    }

    @Test void barometerRawSurvivesUploadRetrySummaryAndLegacyReadWithoutChangingHistory() throws Exception {
        var fixture=json.readTree(Files.readString(Path.of("../run/fixtures/free_barometer_v3.json")));
        var raw=new ArrayList<Input>();
        for(var node:fixture.get("cases").get(0).get("inputs")) raw.add(json.treeToValue(node,Input.class));
        long finalSeq=raw.size()-1;
        mvc.perform(post("/api/v1/runs/sessions/"+id+"/record")
            .with(jwt().jwt(j->j.subject(owner.toString())))
            .contentType("application/json").content(json.writeValueAsString(new Upload(finalSeq,raw))))
            .andExpect(status().isOk());
        assertThat(db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",
            (rs,n)->json.readValue(rs.getString(1),Input.class),id)).containsExactlyElementsOf(raw);
        runs.process(id);
        Result stored=runs.result(owner,id);
        assertThat(stored.stats().elevationGainM()).isCloseTo(3,within(.000001));
        assertThat(stored.stats().elevationSource()).isEqualTo("BAROMETER");
        assertThat(runs.history(owner,new Cursorable(null,null)).content().getFirst().stats()).isEqualTo(stored.stats());
        runs.upload(owner,id,new Upload(finalSeq,raw)); runs.process(id);
        assertThat(runs.result(owner,id)).isEqualTo(stored);
        Input p=raw.stream().filter(v->v.kind()==Kind.BAROMETER).findFirst().orElseThrow();
        var changed=new Input(p.seq(),p.kind(),p.elapsedMs(),p.measuredAt(),null,null,null,null,null,null,null,
            p.sampleEndMs(),null,null,p.pressureHpa()+1,p.pressureAccuracy());
        assertThatThrownBy(()->runs.upload(owner,id,new Upload(finalSeq,List.of(changed)))).isInstanceOf(AppException.class);
        var oldStats=new ResultStats("RESULT_V2",0.0,false,stored.stats().bestLapNumber(),
            stored.stats().bestLapPaceSecondsPerKm(),stored.stats().bestPaceSecondsPerKm());
        var old=new Result(stored.id(),stored.startedAt(),stored.endedAt(),stored.registeredAt(),stored.endReason(),
            stored.metrics(),stored.routeSegments(),stored.laps(),stored.policyVersion(),stored.calculationVersion(),oldStats);
        db.update("UPDATE run.records SET result_json=? WHERE id=?",json.writeValueAsString(old),id);
        Result enriched=runs.result(owner,id);
        assertThat(enriched.stats()).isEqualTo(stored.stats());
        assertThat(enriched.metrics()).isEqualTo(stored.metrics());
        assertThat(enriched.registeredAt()).isEqualTo(stored.registeredAt());
        assertThat(json.readValue(db.queryForObject("SELECT result_json FROM run.records WHERE id=?",String.class,id),Result.class)).isEqualTo(old);
        assertThat(db.queryForObject("SELECT registration_published FROM run.records WHERE id=?",Boolean.class,id)).isTrue();
        assertThatThrownBy(()->runs.result(UUID.randomUUID(),id)).isInstanceOf(AppException.class);
        runs.delete(owner,id);
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,id)).isZero();
        assertThatThrownBy(()->runs.upload(owner,id,new Upload(finalSeq,raw))).isInstanceOf(AppException.class);
    }

    @Test void balancedV3UploadKeepsRawSpikeButStoresCorrectedRouteAndDistance() throws Exception {
        var fixture=json.readTree(Files.readString(Path.of("../run/fixtures/free_motion_v3.json")));
        var source=fixture.get("cases").get(0);
        var raw=new ArrayList<Input>();
        for(var node:source.get("inputs")) {
            Input p=json.treeToValue(node,Input.class);
            raw.add(new Input(p.seq(),p.kind(),p.elapsedMs(),start.plusMillis(p.elapsedMs()),p.location(),p.accuracyM(),
                p.reason(),p.speedMps(),p.speedAccuracyMps(),p.steps(),p.durationMs(),p.sampleEndMs(),p.altitudeM(),p.altitudeAccuracyM(),p.pressureHpa(),p.pressureAccuracy()));
        }
        int last=raw.size()-1;
        runs.upload(owner,id,new Upload(last,raw));
        runs.process(id);
        Result stored=runs.result(owner,id);
        assertThat(stored.calculationVersion()).isEqualTo("PACE_V3");
        // The existing movement window leaves the final single interval unconfirmed.
        assertThat(stored.metrics().distanceM()).isCloseTo(57,within(.001));
        assertThat(stored.routeSegments().stream().flatMap(List::stream)).doesNotContain(raw.get(10).location());
        assertThat(db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",
            (rs,n)->json.readValue(rs.getString(1),Input.class),id)).containsExactlyElementsOf(raw);
        runs.upload(owner,id,new Upload(last,raw)); runs.process(id);
        assertThat(runs.result(owner,id)).isEqualTo(stored);
    }

    @Test void balancedV3HardJumpRemainsSplitAfterUploadStorageAndRetry() throws Exception {
        var fixture=json.readTree(Files.readString(Path.of("../run/fixtures/free_motion_v3.json")));
        var raw=new ArrayList<Input>();
        for(var node:fixture.get("cases").get(1).get("inputs")) {
            Input p=json.treeToValue(node,Input.class);
            raw.add(new Input(p.seq(),p.kind(),p.elapsedMs(),start.plusMillis(p.elapsedMs()),p.location(),p.accuracyM(),
                p.reason(),p.speedMps(),p.speedAccuracyMps(),p.steps(),p.durationMs(),p.sampleEndMs(),p.altitudeM(),p.altitudeAccuracyM(),p.pressureHpa(),p.pressureAccuracy()));
        }
        int last=raw.size()-1;
        runs.upload(owner,id,new Upload(last,raw)); runs.process(id);
        Result stored=runs.result(owner,id);
        assertThat(stored.calculationVersion()).isEqualTo("PACE_V3");
        assertThat(stored.metrics().distanceM()).isCloseTo(54,within(.001));
        assertThat(stored.routeSegments()).hasSize(2);
        assertThat(stored.routeSegments().getFirst()).doesNotContain(raw.get(11).location());
        assertThat(stored.stats().elevationPartial()).isTrue();
        assertThat(db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",
            (rs,n)->json.readValue(rs.getString(1),Input.class),id)).containsExactlyElementsOf(raw);
        runs.upload(owner,id,new Upload(last,raw)); runs.process(id);
        assertThat(runs.result(owner,id)).isEqualTo(stored);
    }

    @Test void sharedGapCasesFinishAndKeepRawInputsAndRegistrationOnRetry(AssertablePublishedEvents events) throws Exception {
        var fixture=json.readTree(Files.readString(Path.of("../run/fixtures/motion_gap_null_v1.json")));
        int registered=0;
        for(var source:fixture.get("cases")) {
            UUID runId=UUID.randomUUID();
            runs.prepare(owner,runId,new Prepare(start,"FREE"));
            var raw=new ArrayList<Input>();
            for(var node:source.get("inputs")) raw.add(json.treeToValue(node,Input.class));
            int last=raw.size()-1;
            runs.upload(owner,runId,new Upload(last,raw)); runs.process(runId);
            assertThat(runs.status(owner,runId).processing()).as(source.get("name").asText()).isEqualTo("DONE");
            Result stored=runs.result(owner,runId);
            var expected=source.get("expected");
            assertThat(stored.calculationVersion()).isEqualTo(raw.getFirst().reason());
            assertThat(stored.metrics().distanceM()).isCloseTo(expected.get("distanceM").asDouble(),within(.000001));
            assertThat(stored.metrics().elapsedMs()).isEqualTo(expected.get("elapsedMs").asLong());
            assertThat(stored.metrics().activeMs()).isEqualTo(expected.get("activeMs").asLong());
            assertThat(stored.metrics().movingMs()).isEqualTo(expected.get("movingMs").asLong());
            assertThat(stored.metrics().gapCount()).isEqualTo(expected.get("gapCount").asInt());
            String summary=db.queryForObject("SELECT summary_json FROM run.records WHERE id=?",String.class,runId);
            runs.upload(owner,runId,new Upload(last,raw)); runs.process(runId);
            assertThat(runs.result(owner,runId)).isEqualTo(stored);
            assertThat(db.queryForObject("SELECT summary_json FROM run.records WHERE id=?",String.class,runId)).isEqualTo(summary);
            assertThat(db.query("SELECT payload FROM run.inputs WHERE session_id=? ORDER BY stream_seq",
                (rs,n)->json.readValue(rs.getString(1),Input.class),runId)).containsExactlyElementsOf(raw);
            assertThat(events.ofType(RunSessionEndedEvent.class)).hasSize(++registered);
        }
    }

    @Test void invalidPressureFieldsRollBackBeforeDurableStorage() {
        for (Input p : List.of(
            new Input(1,Kind.BAROMETER,1000,start.plusMillis(1000),null,null,null,null,null,null,null,1000L,null,null,Double.NaN,3),
            new Input(1,Kind.BAROMETER,1000,start.plusMillis(1000),null,null,null,null,null,null,null,1000L,null,null,1000.0,4),
            new Input(1,Kind.BAROMETER,1000,start.plusMillis(1000),null,null,null,null,null,null,null,1001L,null,null,1000.0,3),
            new Input(1,Kind.BAROMETER,1000,start.plusMillis(1000),null,null,null,null,null,null,null,null,null,null,1000.0,3),
            new Input(1,Kind.GPS,1000,start.plusMillis(1000),inputs.get(1).location(),3.0,null,null,null,null,null,1000L,null,null,1000.0,3))) {
            assertThatThrownBy(()->runs.upload(owner,id,new Upload(9,List.of(inputs.getFirst(),p)))).isInstanceOf(AppException.class);
            assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,id)).isZero();
        }
    }

    @Test void invalidVerticalFieldsNeverPoisonDurableInputs() {
        Input p=inputs.get(1);
        for(Double[] pair:new Double[][]{{Double.NaN,1.0},{Double.POSITIVE_INFINITY,null},{10.0,-1.0},{null,1.0},{10.0,Double.NaN}}) {
            var invalid=new Input(p.seq(),p.kind(),p.elapsedMs(),p.measuredAt(),p.location(),p.accuracyM(),
                p.reason(),p.speedMps(),p.speedAccuracyMps(),null,null,null,pair[0],pair[1]);
            assertThatThrownBy(()->runs.upload(owner,id,new Upload(9,List.of(invalid)))).isInstanceOf(AppException.class);
        }
        var nonGps=new Input(0,Kind.START,0,start,null,null,null,null,null,null,null,null,10.0,1.0);
        assertThatThrownBy(()->runs.upload(owner,id,new Upload(9,List.of(nonGps)))).isInstanceOf(AppException.class);
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs WHERE session_id=?",Long.class,id)).isZero();
        assertThat(runs.status(owner,id).processing()).isEqualTo("PREPARED");
    }

}
