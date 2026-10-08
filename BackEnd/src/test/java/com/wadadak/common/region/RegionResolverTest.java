package com.wadadak.common.region;

import com.wadadak.TestcontainersConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 시드 마이그레이션(scripts/region/build-seed.sh로 생성)이 적용된 DB에서 확인한다.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class RegionResolverTest {

    @Autowired
    RegionResolver regionResolver;

    @Test
    void resolvesSunMoonUniversityToTangjeong() {
        // 선문대 아산캠퍼스: 충청남도 아산시 탕정면
        assertThat(regionResolver.resolveCode(36.7990, 127.0750)).contains("4420033000");
    }

    @Test
    void returnsEmptyAtSea() {
        assertThat(regionResolver.resolveCode(36.0, 125.0)).isEmpty();
    }
}
