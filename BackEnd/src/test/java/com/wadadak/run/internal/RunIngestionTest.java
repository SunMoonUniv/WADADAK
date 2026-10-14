package com.wadadak.run.internal;

import com.wadadak.TestcontainersConfiguration;
import com.wadadak.common.exception.AppException;
import com.wadadak.run.RunContracts.*;
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
    @Autowired RunService runs;
    @Autowired JdbcTemplate db;
    @Autowired JsonMapper json;
    @Autowired MockMvc mvc;
    @MockitoBean RunProcessingWorker worker;
    final UUID owner=UUID.randomUUID(),id=UUID.randomUUID();
    final Instant start=Instant.parse("2026-10-12T00:00:00Z");
    List<Input> inputs;
    @BeforeEach void prepare() throws Exception {
        db.update("DELETE FROM run.deleted_records"); db.update("DELETE FROM run.records"); db.update("DELETE FROM run.inputs"); db.update("DELETE FROM run.sessions");
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
    @Test void conflictingBatchRollsBackAndAnotherOwnerCannotAccess() {
        runs.upload(owner,id,new Upload(9,List.of(inputs.getFirst())));
        var changed=new Input(0,Kind.START,100,start.plusMillis(100),null,null,null);
        assertThatThrownBy(()->runs.upload(owner,id,new Upload(9,List.of(inputs.get(1),changed)))).isInstanceOf(AppException.class);
        assertThat(db.queryForObject("SELECT count(*) FROM run.inputs",Long.class)).isEqualTo(1);
        assertThatThrownBy(()->runs.status(UUID.randomUUID(),id)).isInstanceOf(AppException.class);
        assertThatThrownBy(()->runs.prepare(UUID.randomUUID(),id,new Prepare(start,"FREE"))).isInstanceOf(AppException.class);
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
        Page first = runs.history(owner,null);
        Page second = runs.history(owner,first.nextCursor());
        assertThat(first.items()).hasSize(20);
        assertThat(second.items()).hasSize(1);
        assertThat(second.nextCursor()).isNull();
        List<UUID> all = new ArrayList<>();
        first.items().forEach(record -> all.add(record.id()));
        second.items().forEach(record -> all.add(record.id()));
        assertThat(all).doesNotHaveDuplicates();
        assertThat(json.writeValueAsString(first)).doesNotContain("routeSegments");
        assertThat(runs.result(owner,all.getFirst()).routeSegments()).isNotEmpty();
        assertThat(runs.history(UUID.randomUUID(),null).items()).isEmpty();
        assertThatThrownBy(() -> runs.history(owner,"invalid-cursor")).isInstanceOf(AppException.class);
    }
    @Test void zeroDistanceAndImpossibleStateNeverBecomePersonalRecords() {
        var pause=new Input(1,Kind.PAUSE,1000,start.plusMillis(1000),null,null,null);
        var end=new Input(2,Kind.END,1000,start.plusMillis(1000),null,null,"USER");
        runs.upload(owner,id,new Upload(2,List.of(inputs.getFirst(),pause,end))); runs.process(id);
        assertThat(runs.status(owner,id).failure()).isEqualTo("ZERO_DISTANCE");
        assertThat(runs.history(owner,null).items()).isEmpty();
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
        assertThat(runs.history(owner,null).items()).isEmpty();
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
        assertThat(runs.history(owner,null).items()).isEmpty();
        assertThat(db.queryForObject("SELECT count(*) FROM run.records WHERE id=?",Long.class,id)).isZero();
    }
    @Test void deleteEndpointConfirmsReservationAndHidesRecordFromOtherOwners() throws Exception {
        mvc.perform(delete("/api/v1/runs/records/"+id).with(jwt().jwt(t->t.subject(owner.toString()))))
            .andExpect(status().isOk()).andExpect(jsonPath("$.data.deleted").value(true));
        mvc.perform(delete("/api/v1/runs/records/"+id).with(jwt().jwt(t->t.subject(UUID.randomUUID().toString()))))
            .andExpect(status().isNotFound());
    }

}
