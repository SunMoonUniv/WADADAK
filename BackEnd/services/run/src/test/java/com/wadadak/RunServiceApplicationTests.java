package com.wadadak;

import net.javacrumbs.shedlock.core.LockConfiguration;
import net.javacrumbs.shedlock.core.LockProvider;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

import java.time.Duration;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * run 서비스가 run 마이그레이션만 적용한 빈 DB에서 뜨는지(MSA 분리 3단계, deploy/MSA 분리 준비와 CI·CD 1.1).
 * 다른 스키마 테이블이 없으므로 run 코드가 경계를 어기면 여기서 실패한다.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RunServiceApplicationTests {

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    LockProvider lockProvider;

    @Test
    void migratesOnlyRunSchema() {
        assertThat(jdbc.queryForList("SELECT schema_name FROM information_schema.schemata", String.class))
                .contains("run").doesNotContain("common", "course", "member", "ranking", "review", "notification");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM run.flyway_schema_history", Integer.class)).isPositive();
    }

    @Test
    void schedulerLocksLiveInRunSchema() {
        var lock = lockProvider.lock(new LockConfiguration(Instant.now(), "run-service-test",
                Duration.ofSeconds(30), Duration.ZERO));

        assertThat(lock).isPresent();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM run.shedlock WHERE name = 'run-service-test'", Integer.class))
                .isEqualTo(1);
        lock.get().unlock();
    }
}
