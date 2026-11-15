package com.wadadak;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.modulith.Modulithic;

/**
 * run 서비스(MSA 분리 3단계, 개발 정책 11.3). run 모듈과 공유 jar · 계약 jar만 담는다.
 * 3단계에서는 빌드 · 테스트만 하고 배포하지 않는다. 그동안 run은 core 서비스 안에서 돈다(services/core/build.gradle).
 */
@Modulithic(sharedModules = "common")
@SpringBootApplication
public class RunServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(RunServiceApplication.class, args);
    }
}
